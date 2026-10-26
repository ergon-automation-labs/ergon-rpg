defmodule BotArmyRpg.Handlers.SceneNarrationAsyncTest do
  @moduledoc """
  A scene narration is a model round trip, and the page that asks for one must not have
  to hold a socket open for it.

  Her sentence, 2026-10-26: *"oh the 27b model doesn't answer in 3 seconds - we want a
  wait for the answer asynchronously"*. The defect behind it was a 3 s deadline on
  `llm.prompt.submit` — measured against the *real* prompt at 7.5 s and 31.6 s — and the
  runtime's circuit breaker answers the first timeout with a 60 s cooldown, so one slow
  answer turned the next minute of narration into the template. mini logged exactly that:
  `rpg:gm:llm.narrate: timeout, cooldown 60000ms`.

  So `rpg.scene.narrate` has two shapes, and the caller declares which it can hold —
  the fleet's own idiom (`llm.request.chat` with `"async": true`):

    * `"async" => true` answers **at once** with `pending: true`, writes the ask down
      before the model is asked, and finishes the prose in the background;
    * without it the call still waits — with a timeout a model can meet.

  `rpg.scene.narration.get` reads the prose back. Three states, not two: `writing` is a
  different fact from `none`, and a page that conflated them would draw an empty card
  while the model was still thinking.
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.GMHandler

  @tenant "00000000-0000-0000-0000-000000000001"
  @session "00000000-0000-0000-0000-0000000000se"
  @prose "The hall lay open to the sky."

  # Answers prose the way the llm bot does (`completion`), and reports the options it was
  # asked with — the timeout is the thing this file is about, so it is asserted, not
  # assumed.
  defmodule ProsePublisher do
    @moduledoc false
    def request("llm.prompt.submit", _payload, opts) do
      # The caller's pid, not `self()`: the async path asks from a Task, and the test is
      # the process that wants to hear about it.
      send(Application.get_env(:bot_army_rpg, :prose_probe), {:asked_with, opts})
      {:ok, %{"completion" => "The hall lay open to the sky."}}
    end

    def request(_subject, _payload, _opts), do: {:error, :no_bridge}
    def publish(_subject, _payload, _opts), do: :ok
  end

  # A publisher that would make an awaited call expensive: if the async path waited for it
  # at all, the elapsed assertion below would fail.
  defmodule SlowPublisher do
    @moduledoc false
    def request("llm.prompt.submit", _payload, _opts) do
      Process.sleep(600)
      {:ok, %{"completion" => "Slow prose."}}
    end

    def request(_subject, _payload, _opts), do: {:error, :no_bridge}
    def publish(_subject, _payload, _opts), do: :ok
  end

  setup :verify_on_exit!

  setup do
    # The background half of an async narration is its own process, so the mocks have to
    # be shared with it and the publisher has to know where to report.
    set_mox_global()

    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)
    Application.put_env(:bot_army_rpg, :prose_probe, self())

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :prose_probe)
      Application.delete_env(:bot_army_rpg, :nats_publisher)
    end)

    :ok
  end

  defp payload(extra \\ %{}) do
    Map.merge(%{"tenant_id" => @tenant, "session_id" => @session}, extra)
  end

  # A table with no narration recorded yet. `metadata` is the map the handler merges into,
  # so tests can watch it change.
  defp stub_session(metadata \\ %{}) do
    stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
      {:ok,
       %{
         "id" => @session,
         "status" => "active",
         "scene_description" => "Cyberpunk Nexus",
         "metadata" => metadata
       }}
    end)
  end

  defp stub_writes_to_probe do
    probe = Application.get_env(:bot_army_rpg, :prose_probe)

    stub(BotArmyRpg.SessionStoreMock, :update, fn _tenant, _session, changes ->
      send(probe, {:narration_written, changes["metadata"]["narration"]})
      {:ok, Map.merge(%{"id" => @session}, changes)}
    end)
  end

  defp stub_table_and_theme do
    stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant ->
      {:ok, %{"setting" => "Neon Nexus City", "tone" => "chrome dreams", "vocabulary" => %{}}}
    end)

    stub(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn _tenant, _session -> {:ok, []} end)
  end

  defp use_publisher(module), do: Application.put_env(:bot_army_rpg, :nats_publisher, module)

  # An async narration writes twice: the ask (`writing`) before the model is called, and
  # the outcome after. Waiting for the outcome is also what keeps a background task from
  # calling a mock after its test has gone — `verify_on_exit!` is what turns that into a
  # failure rather than a flake.
  defp assert_settled(timeout \\ 2_000) do
    receive do
      # The ask itself, which every async narration writes first.
      {:narration_written, %{"status" => "writing"}} ->
        assert_settled(timeout)

      {:narration_written, %{"status" => status} = narration} ->
        assert status in ["ready", "failed"],
               "the narration settled as #{status}: #{inspect(narration)}"

        narration
    after
      timeout -> flunk("the narration never settled")
    end
  end

  describe "async: true — the ask is answered at once" do
    test "a slow model does not make the press slow" do
      stub_session()
      stub_table_and_theme()
      stub_writes_to_probe()
      use_publisher(SlowPublisher)

      {micros, answer} =
        :timer.tc(fn ->
          GMHandler.handle_scene_narrate(payload(%{"async" => true}))
        end)

      assert {:ok, %{"pending" => true, "session_id" => @session, "asked_at" => asked_at}} =
               answer

      assert is_binary(asked_at)
      assert micros < 300_000, "the async path waited #{div(micros, 1000)} ms on a 600 ms model"

      assert_receive {:narration_written, %{"status" => "writing"}}, 500
      assert_settled()
    end

    test "the ask is written down as `writing` before the model is asked" do
      stub_session()
      stub_table_and_theme()
      stub_writes_to_probe()
      use_publisher(SlowPublisher)

      assert {:ok, %{"pending" => true}} =
               GMHandler.handle_scene_narrate(payload(%{"async" => true}))

      assert_receive {:narration_written, %{"status" => "writing", "narration" => nil}}, 500
      assert_settled()
    end

    test "the prose lands in the record when the model answers, without anyone waiting" do
      stub_session()
      stub_table_and_theme()
      stub_writes_to_probe()
      use_publisher(ProsePublisher)

      assert {:ok, %{"pending" => true}} =
               GMHandler.handle_scene_narrate(payload(%{"async" => true}))

      assert %{"status" => "ready", "narration" => @prose} = assert_settled()
    end

    test "a narration that fails is written down as failed, with its reason" do
      stub_session()
      stub_writes_to_probe()
      use_publisher(ProsePublisher)

      # The theme is what this background pass reads first, so a theme that will not
      # answer is the failure — and the record must say so rather than stay `writing`
      # forever, which a page would draw as "the GM is writing" for the rest of the day.
      stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:error, :not_found} end)

      assert {:ok, %{"pending" => true}} =
               GMHandler.handle_scene_narrate(payload(%{"async" => true}))

      assert %{"status" => "failed", "error" => "not_found", "narration" => nil} =
               assert_settled()
    end
  end

  describe "without the flag — the call still waits, for as long as a model needs" do
    test "the answer is the narration, and the timeout is not three seconds" do
      stub_session()
      stub_table_and_theme()
      stub_writes_to_probe()
      use_publisher(ProsePublisher)

      assert {:ok, %{"narration" => @prose}} = GMHandler.handle_scene_narrate(payload())

      assert_receive {:asked_with, opts}, 500
      timeout = Keyword.fetch!(opts, :timeout_ms)

      assert timeout >= 60_000,
             "the timeout is #{timeout} ms — a local model is not late at three seconds"
    end
  end

  describe "rpg.scene.narration.get — three states, not two" do
    test "reads back the prose that was written" do
      stub_session(%{
        "narration" => %{
          "status" => "ready",
          "narration" => @prose,
          "asked_at" => "2026-10-26T15:00:00Z",
          "ready_at" => "2026-10-26T15:00:31Z"
        }
      })

      assert {:ok, answer} = GMHandler.handle_scene_narration_get(payload())
      assert answer["status"] == "ready"
      assert answer["narration"] == @prose
      assert answer["ready_at"] == "2026-10-26T15:00:31Z"
    end

    test "a model still thinking is `writing`, not an empty answer" do
      stub_session(%{"narration" => %{"status" => "writing", "narration" => nil}})

      assert {:ok, %{"status" => "writing", "narration" => nil}} =
               GMHandler.handle_scene_narration_get(payload())
    end

    test "a table nobody has narrated is `none`" do
      stub_session()

      assert {:ok, %{"status" => "none", "narration" => nil}} =
               GMHandler.handle_scene_narration_get(payload())
    end

    test "a failure is reported as a failure, with the reason" do
      stub_session(%{
        "narration" => %{"status" => "failed", "narration" => nil, "error" => "timeout"}
      })

      assert {:ok, %{"status" => "failed", "error" => "timeout"}} =
               GMHandler.handle_scene_narration_get(payload())
    end

    test "a missing session is refused, not answered with `none`" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session -> {:error, :not_found} end)

      assert {:error, :not_found} = GMHandler.handle_scene_narration_get(payload())
    end
  end
end
