defmodule BotArmyRpg.NATS.ConsumerDispatchTest do
  use ExUnit.Case
  @moduletag :nats

  import ExUnit.CaptureLog
  import Mox

  alias BotArmyRpg.NATS.Consumer

  # A store whose process is not running. The call exits with
  # {:noproc, {GenServer, :call, [StoreNotRunning, ...]}} - the shape a dead store sends,
  # and one `rescue` alone does not catch.
  defmodule StoreNotRunning do
    def get_current(tenant_id), do: GenServer.call(__MODULE__, {:get_current, tenant_id})
  end

  setup :verify_on_exit!

  describe "the dispatch boundary" do
    test "a handler that raises costs its own request, not the Consumer" do
      stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant_id ->
        raise "the store fell over"
      end)

      Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)
      on_exit(fn -> Application.delete_env(:bot_army_rpg, :theme_store) end)

      log =
        capture_log(fn ->
          assert {:error, :handler_crashed} =
                   Consumer.dispatch("rpg.world.snapshot", %{"tenant_id" => "the-tenant"})
        end)

      # The refusal names the route, so an operator can find it without a crash dump.
      assert log =~ "rpg.world.snapshot"
      assert log =~ "the store fell over"

      # The boundary survived the raise: an unrelated route still answers, in the same
      # process. That is the whole point - a raise used to kill the Consumer and silence
      # every route until someone restarted the bot.
      assert {:ok, %{"name" => name}} =
               Consumer.dispatch("rpg.loot.generate", %{"source" => "gtd_task"})

      assert is_binary(name)
    end

    test "a store process that is not running is a refusal, not a dead Consumer" do
      Application.put_env(:bot_army_rpg, :theme_store, StoreNotRunning)
      on_exit(fn -> Application.delete_env(:bot_army_rpg, :theme_store) end)

      log =
        capture_log(fn ->
          assert {:error, :handler_crashed} =
                   Consumer.dispatch("rpg.world.snapshot", %{"tenant_id" => "the-tenant"})
        end)

      # The exit's shape is kept and its arguments are dropped: never `inspect/1` a call's
      # reason wholesale, or the log carries whatever the handler was arguing about.
      assert log =~ ":noproc"
      refute log =~ "the-tenant"
    end

    test "every :request_reply subject in the manifest reaches a clause" do
      subjects = Consumer.subjects() |> Enum.filter(&(&1.type == :request_reply))

      assert length(subjects) > 40,
             "the manifest should still declare the request replies (got #{length(subjects)})"

      capture_log(fn ->
        for %{subject: subject} <- subjects do
          # A subject with no clause falls through to {:error, :unknown_subject}. Anything
          # else - a payload, or an honest refusal - proves a clause exists. That is the
          # invariant: the manifest and the dispatch table cannot drift apart in silence.
          #
          # Nothing here can write: in the test env every store is a Mox double with no
          # expectations, so the first store call raises and the boundary refuses it.
          assert Consumer.dispatch(subject, %{}) != {:error, :unknown_subject}, subject
        end
      end)
    end
  end
end
