defmodule BotArmyRpg.Handlers.SceneFactHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  alias BotArmyRpg.Handlers.SceneFactHandler
  alias BotArmyRpg.{Identity, PartyStoreMock, SceneFactStoreMock, SessionStoreMock}

  defmodule StubPublisher do
    @moduledoc false
    def publish(subject, payload, opts) do
      send(self(), {:published, subject, payload, opts})
      :ok
    end
  end

  defmodule FailingPublisher do
    @moduledoc false
    def publish(_subject, _payload, _opts), do: {:error, :no_connection_manager}
  end

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :session_store)
    end)

    :ok
  end

  describe "handle_add/1" do
    test "appends a scene fact" do
      session_id = Ecto.UUID.generate()

      fact = %{
        "id" => Ecto.UUID.generate(),
        "session_id" => session_id,
        "content" => "The door creaks open",
        "tenant_id" => BotArmyLibraryRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SceneFactStoreMock
      |> expect(:append, fn _payload -> {:ok, fact} end)

      # A turn is the window being used, so the window's clock moves with it.
      BotArmyRpg.SessionStoreMock
      |> expect(:touch, fn tenant, ^session_id ->
        assert tenant == BotArmyLibraryRuntime.Tenant.default_tenant_id()
        {:ok, %{"id" => session_id}}
      end)

      message = %{"payload" => %{"session_id" => session_id, "content" => "The door creaks open"}}

      assert {:ok, ^fact} = BotArmyRpg.Handlers.SceneFactHandler.handle_add(message)
    end

    test "a window whose clock could not move still stores the turn" do
      session_id = Ecto.UUID.generate()

      fact = %{"id" => Ecto.UUID.generate(), "session_id" => session_id, "content" => "a line"}

      expect(BotArmyRpg.SceneFactStoreMock, :append, fn _payload -> {:ok, fact} end)

      expect(BotArmyRpg.SessionStoreMock, :touch, fn _tenant, ^session_id ->
        {:error, :not_found}
      end)

      # Best effort: the turn is stored and told so; only the ordering is left stale,
      # and that is logged rather than hidden.
      assert {:ok, ^fact} =
               BotArmyRpg.Handlers.SceneFactHandler.handle_add(%{
                 "payload" => %{"session_id" => session_id, "content" => "a line"}
               })
    end
  end

  # Every fact the store is handed, so that a note the machinery wrote is visible as a
  # second append rather than as something a test has to assume did not happen.
  defp stub_fact_store do
    stub(SceneFactStoreMock, :append, fn payload ->
      send(self(), {:appended, payload})
      {:ok, Map.put(payload, "id", Ecto.UUID.generate())}
    end)
  end

  defp expect_a_window(session_id) do
    expect(SessionStoreMock, :touch, fn _tenant, ^session_id ->
      {:ok, %{"id" => session_id}}
    end)
  end

  defp expect_party_narrated_by(bot_id) do
    expect(PartyStoreMock, :get_party, fn _tenant, keyed ->
      # The identity a window's line is written under is the name an operator uses for
      # herself, and the party is keyed by the UUID that name normalizes to.
      assert keyed == Identity.normalize_user_id("abby")

      {:ok,
       %{
         "members" => [
           %{"character_id" => "c-member", "bot_id" => "gtd_bot", "role" => "companion"},
           %{"character_id" => "c-narrator", "bot_id" => bot_id, "role" => "narrator"}
         ]
       }}
    end)
  end

  defp a_line(session_id, extra) do
    Map.merge(%{"session_id" => session_id, "content" => "is anybody in there"}, extra)
  end

  describe "handle_add/1 and the window's chat" do
    setup do
      Application.put_env(:bot_army_rpg, :party_store, PartyStoreMock)
      Application.put_env(:bot_army_rpg, :nats_publisher, StubPublisher)

      on_exit(fn ->
        Application.delete_env(:bot_army_rpg, :party_store)
        Application.delete_env(:bot_army_rpg, :nats_publisher)
      end)

      :ok
    end

    test "a line in a window whose party names a narrator is handed to her, and noted" do
      session_id = Ecto.UUID.generate()

      stub_fact_store()
      expect_a_window(session_id)
      expect_party_narrated_by("companion_bot")

      assert {:ok, fact} =
               SceneFactHandler.handle_add(%{
                 "payload" => a_line(session_id, %{"user_id" => "abby", "source" => "operator"})
               })

      assert fact["content"] == "is anybody in there"

      assert_received {:published, subject, payload, opts}
      assert subject == "rpg.narration.your_turn"
      assert opts[:tenant_id] == BotArmyLibraryRuntime.Tenant.default_tenant_id()

      assert payload == %{
               "kind" => "chat",
               "session_id" => session_id,
               "character_id" => "c-narrator",
               "bot_id" => "companion_bot",
               "content" => "is anybody in there",
               "speaker" => "operator"
             }

      # The line (what the store was handed) and then the note (what the window reads as
      # "she has not said anything yet").
      assert_received {:appended, stored_line}
      assert stored_line["content"] == "is anybody in there"

      assert_received {:appended, note}
      assert note["category"] == "narration_asked"
      assert note["source"] == "system"
      assert note["content"] == "[narration_asked] companion_bot"
    end

    test "a line in a window whose party names no narrator is stored and asks nobody" do
      session_id = Ecto.UUID.generate()

      stub_fact_store()
      expect_a_window(session_id)

      expect(PartyStoreMock, :get_party, fn _tenant, _keyed ->
        {:ok, %{"members" => [%{"character_id" => "c1", "bot_id" => "gtd_bot"}]}}
      end)

      assert {:ok, _fact} =
               SceneFactHandler.handle_add(%{
                 "payload" => a_line(session_id, %{"user_id" => "abby", "source" => "operator"})
               })

      refute_received {:published, _, _, _}
      assert_received {:appended, _stored_line}
      refute_received {:appended, _note}
    end

    test "a note the machinery wrote is not a line anybody said, so nobody is asked" do
      session_id = Ecto.UUID.generate()

      stub_fact_store()
      expect_a_window(session_id)

      assert {:ok, _fact} =
               SceneFactHandler.handle_add(%{
                 "payload" => a_line(session_id, %{"user_id" => "abby", "source" => "system"})
               })

      refute_received {:published, _, _, _}
      assert_received {:appended, _stored_line}
      refute_received {:appended, _note}
    end

    test "an ask the bus would not take is not a lost line: it is stored, and told so" do
      session_id = Ecto.UUID.generate()

      stub_fact_store()
      expect_a_window(session_id)
      expect_party_narrated_by("companion_bot")
      Application.put_env(:bot_army_rpg, :nats_publisher, FailingPublisher)

      # The line is already stored by the time the ask is attempted, so an ask nobody
      # received is a member nobody asked — the window says her words are not there yet,
      # which is true — and never a lost line.
      assert {:ok, fact} =
               SceneFactHandler.handle_add(%{
                 "payload" => a_line(session_id, %{"user_id" => "abby", "source" => "operator"})
               })

      assert fact["content"] == "is anybody in there"
      assert_received {:appended, _stored_line}
      refute_received {:appended, _note}
    end
  end

  describe "handle_list/1" do
    test "lists facts for a session" do
      session_id = Ecto.UUID.generate()

      facts = [
        %{"id" => Ecto.UUID.generate(), "session_id" => session_id, "content" => "A shadow moves"}
      ]

      SceneFactStoreMock
      |> expect(:list_for_session, fn _tenant_id, ^session_id -> {:ok, facts} end)

      message = %{"payload" => %{"session_id" => session_id}}

      assert {:ok, ^facts} = SceneFactHandler.handle_list(message)
    end
  end
end
