defmodule BotArmyRpg.Handlers.GMHandlerTest do
  @moduledoc """
  Turn order, and what a turn call does when the table is not set.

  Six live subjects (`rpg.turn.*`, `rpg.action.*`, `rpg.scene.narrate`) had no test. The
  handler already resolves its stores through `Application.get_env/3` at call time, so
  unlike the campaign routes this one can be tested properly today — with the four mocks
  the suite already defines.

  What these tests are really about is the **gate**: a turn only exists inside an active
  session. Every route that mutates turn state has to refuse a session that is missing or
  paused *before* it reaches a store or a publish, because a turn taken in a dead session
  is a lie the table tells the players. `rpg.turn.whose` is the deliberate exception: it is
  a read, so a paused session still has an answer, and the asymmetry is pinned below so it
  stays a decision rather than an accident.

  The happy path that writes a fact (`rpg.action.resolve`) is exercised: the run has no
  broker, so the publish that follows the write is an error the handler already ignores,
  and the write itself is asserted through the store double — including that the prose
  written is the prose the caller is told.
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.GMHandler
  alias BotArmyRpg.PartyNarration

  # A bus that takes the ask (the publish is not what these tests are about), and a bus
  # that will not — rpg's own wrapper's shape for a publish that failed. `request/3` is the
  # other half of the seam (`GM.Dice` asks the bridge for a roll): both answer "no bridge",
  # so the dice fall back to the local roller exactly as they do without a broker.
  defmodule OkPublisher do
    @moduledoc false
    def publish(_subject, _payload, _opts), do: :ok
    def request(_subject, _payload, _opts), do: {:error, :no_bridge}
  end

  defmodule DownPublisher do
    @moduledoc false
    def publish(_subject, _payload, _opts), do: {:error, :no_connection_manager}
    def request(_subject, _payload, _opts), do: {:error, :no_bridge}
  end

  @tenant "00000000-0000-0000-0000-000000000001"
  @session "00000000-0000-0000-0000-0000000000se"
  @character "00000000-0000-0000-0000-0000000000ch"
  @user "00000000-0000-0000-0000-000000000002"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)
    Application.put_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStoreMock)

    # No party unless a test says so: the sessions these routes read carry no user, so the
    # read answers "no party" without asking the store (pinned in `PartyReadTest`).
    Mox.stub(BotArmyRpg.PartyStoreMock, :get_party, fn _tenant, _user -> {:error, :not_found} end)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :party_store)
    end)

    :ok
  end

  defp payload(extra \\ %{}) do
    Map.merge(%{"tenant_id" => @tenant, "session_id" => @session}, extra)
  end

  # The six routes as the Consumer dispatches them.
  defp mutating_routes do
    [
      {"rpg.turn.start_round", &GMHandler.handle_turn_start_round/1},
      {"rpg.turn.next", &GMHandler.handle_turn_next/1},
      {"rpg.action.declare", &GMHandler.handle_action_declare/1},
      {"rpg.action.resolve", &GMHandler.handle_action_resolve/1},
      {"rpg.scene.narrate", &GMHandler.handle_scene_narrate/1}
    ]
  end

  describe "a session that cannot be found" do
    test "every mutating route reports the missing session instead of raising" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session -> {:error, :not_found} end)

      for {subject, fun} <- mutating_routes() do
        assert {:error, :not_found} = fun.(payload(%{"character_id" => @character})),
               "#{subject} did not report a missing session"
      end
    end

    test "rpg.turn.whose reports it too" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session -> {:error, :not_found} end)

      assert {:error, :not_found} = GMHandler.handle_turn_whose(payload())
    end
  end

  describe "a session that is not active" do
    test "every mutating route refuses with :session_not_active" do
      # The gate. A paused table is not a table where a turn may be taken — and the refusal
      # has to arrive before any store write or publish.
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok, %{"status" => "paused", "id" => @session, "metadata" => %{}}}
      end)

      for {subject, fun} <- mutating_routes() do
        assert {:error, :session_not_active} =
                 fun.(payload(%{"character_id" => @character})),
               "#{subject} took a turn in a paused session"
      end
    end

    test "rpg.turn.whose still answers, because it only reads" do
      # Pinned asymmetry: the read has an answer for a paused session, the writes do not.
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok,
         %{
           "status" => "paused",
           "id" => @session,
           "metadata" => %{
             "turn_state" => %{
               "round" => 3,
               "active_index" => 1,
               "turn_order" => [@character, "second-character"]
             }
           }
         }}
      end)

      assert {:ok, answer} = GMHandler.handle_turn_whose(payload())
      assert answer["round"] == 3
      assert answer["active_index"] == 1
      assert answer["turn_order"] == [@character, "second-character"]
      assert answer["current_actor"]["character_id"] == "second-character"
    end
  end

  describe "rpg.action.declare" do
    test "an active session with an unknown character is refused before anything is written" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok, %{"status" => "active", "id" => @session, "metadata" => %{}}}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :get, fn _tenant, _character -> {:error, :not_found} end)

      assert {:error, :not_found} =
               GMHandler.handle_action_declare(
                 payload(%{"character_id" => @character, "action_type" => "attack"})
               )
    end
  end

  describe "a session with no turn state yet" do
    test "rpg.turn.whose answers with nothing rather than inventing an actor" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok, %{"status" => "active", "id" => @session, "metadata" => %{}}}
      end)

      assert {:ok, answer} = GMHandler.handle_turn_whose(payload())
      assert answer["current_actor"] == nil
      assert answer["round"] == nil
      assert answer["turn_order"] == nil
    end
  end

  describe "the name on a turn" do
    test "the GM's own prose is signed by the GM, even when a bot plays the character" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok,
         %{
           "status" => "active",
           "id" => @session,
           "metadata" => %{},
           "scene_description" => "a hall with one long table"
         }}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :get, fn _tenant, @character ->
        {:ok,
         %{
           "id" => @character,
           "name" => "The Lorekeeper",
           "class" => "Sage",
           "bot_id" => "gtd_bot",
           "stats" => %{}
         }}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :update, fn _tenant, _character, attrs ->
        {:ok, attrs}
      end)

      stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:ok, %{}} end)

      stub(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn _tenant, _session -> {:ok, []} end)

      stub(BotArmyRpg.SessionStoreMock, :update, fn _tenant, _session, attrs -> {:ok, attrs} end)

      expect(BotArmyRpg.SceneFactStoreMock, :append, fn fact ->
        # The handler already wrote the fact when the reply comes back, so the content —
        # which is the narration the caller is told — is compared after the call.
        send(self(), {:appended, fact})
        {:ok, %{}}
      end)

      assert {:ok, result} =
               GMHandler.handle_action_resolve(
                 payload(%{
                   "character_id" => @character,
                   "action" => %{"action_type" => "inspect"}
                 })
               )

      assert_received {:appended, fact}

      # The turn and the reply are one thing: the window must read exactly the prose the
      # caller was told, not a second rendering of it.
      assert is_binary(fact["content"]) and fact["content"] != ""
      assert fact["content"] == result["narration"]
      assert fact["category"] == "narration"
      assert fact["source"] == "gm"
      refute fact["source"] == "gtd_bot"
      assert fact["session_id"] == @session
    end

    test "a character no bot plays is signed the same way" do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok,
         %{
           "status" => "active",
           "id" => @session,
           "metadata" => %{},
           "scene_description" => "a hall with one long table"
         }}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :get, fn _tenant, @character ->
        {:ok, %{"id" => @character, "name" => "Louiza", "class" => "Sage", "stats" => %{}}}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :update, fn _tenant, _character, attrs ->
        {:ok, attrs}
      end)

      stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:ok, %{}} end)

      stub(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn _tenant, _session -> {:ok, []} end)

      stub(BotArmyRpg.SessionStoreMock, :update, fn _tenant, _session, attrs -> {:ok, attrs} end)

      expect(BotArmyRpg.SceneFactStoreMock, :append, fn fact ->
        send(self(), {:appended, fact})
        {:ok, %{}}
      end)

      assert {:ok, _result} =
               GMHandler.handle_action_resolve(
                 payload(%{
                   "character_id" => @character,
                   "action" => %{"action_type" => "inspect"}
                 })
               )

      assert_received {:appended, fact}
      assert fact["source"] == "gm"
    end
  end

  describe "the turn a narrator is asked for" do
    # A session a party can be keyed by: the narrator is looked up under its user.
    defp stub_session do
      stub(BotArmyRpg.SessionStoreMock, :get, fn _tenant, _session ->
        {:ok,
         %{
           "status" => "active",
           "id" => @session,
           "user_id" => @user,
           "metadata" => %{"turn_state" => %{"round" => 2}},
           "scene_description" => "a hall with one long table"
         }}
      end)

      stub(BotArmyRpg.SessionStoreMock, :update, fn _tenant, _session, attrs -> {:ok, attrs} end)
    end

    defp stub_table do
      stub(BotArmyRpg.CharacterStoreMock, :get, fn _tenant, @character ->
        {:ok,
         %{
           "id" => @character,
           "name" => "The Lorekeeper",
           "class" => "Sage",
           "bot_id" => "gtd_bot",
           "stats" => %{}
         }}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :update, fn _tenant, _character, attrs ->
        {:ok, attrs}
      end)

      stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:ok, %{}} end)

      stub(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn _tenant, _session -> {:ok, []} end)
    end

    test "a party that names a narrator is asked, and the only thing written is the note that names her" do
      stub_session()
      stub_table()
      bus_takes_the_ask()

      expect(BotArmyRpg.PartyStoreMock, :get_party, fn _tenant, @user ->
        {:ok, %{"members" => [narrator_member()]}}
      end)

      # Exactly once, and it is the note: the words are hers to write, if she writes them,
      # so no fact carries a sentence in her name. A stub would not prove that — an
      # `expect` fails if the turn writes prose as well.
      expect(BotArmyRpg.SceneFactStoreMock, :append, fn fact ->
        assert fact["content"] == PartyNarration.note_content(narrator_member())
        assert fact["category"] == PartyNarration.asked_category()
        assert fact["source"] == "system"
        assert fact["session_id"] == @session
        assert fact["tenant_id"] == @tenant

        send(self(), {:appended, fact})
        {:ok, Map.put(fact, "id", "note-1")}
      end)

      assert {:ok, result} =
               GMHandler.handle_action_resolve(
                 payload(%{
                   "character_id" => @character,
                   "action" => %{"action_type" => "inspect"}
                 })
               )

      assert_received {:appended, note}
      assert note["content"] == "[narration_asked] companion_bot"

      # The words are hers to write, if she writes them: rpg reports the turn as having
      # none rather than inventing prose and signing it.
      assert result["narration"] == nil
      assert result["narrator"] == "companion_bot"
    end

    test "an ask that cannot be published leaves the GM narrating" do
      stub_session()
      stub_table()
      bus_will_not_take_the_ask()

      expect(BotArmyRpg.PartyStoreMock, :get_party, fn _tenant, @user ->
        {:ok, %{"members" => [narrator_member()]}}
      end)

      # Nothing reached her, so nothing is pending and the note is not written: the one
      # append is the GM's prose. A bus that is down must not take the table's words away.
      expect(BotArmyRpg.SceneFactStoreMock, :append, fn fact ->
        send(self(), {:appended, fact})
        {:ok, Map.put(fact, "id", "f-1")}
      end)

      assert {:ok, result} =
               GMHandler.handle_action_resolve(
                 payload(%{
                   "character_id" => @character,
                   "action" => %{"action_type" => "inspect"}
                 })
               )

      assert_received {:appended, fact}
      assert fact["source"] == "gm"
      assert fact["content"] == result["narration"]
      refute fact["content"] == PartyNarration.note_content(narrator_member())

      # She is still the party's narrator — the report does not become "nobody narrates"
      # just because rpg could not reach her.
      assert result["narrator"] == "companion_bot"
    end

    defp narrator_member do
      %{"character_id" => "c-narrator", "bot_id" => "companion_bot", "role" => "narrator"}
    end

    defp bus_takes_the_ask do
      Application.put_env(:bot_army_rpg, :nats_publisher, OkPublisher)
      on_exit(fn -> Application.delete_env(:bot_army_rpg, :nats_publisher) end)
    end

    defp bus_will_not_take_the_ask do
      Application.put_env(:bot_army_rpg, :nats_publisher, DownPublisher)
      on_exit(fn -> Application.delete_env(:bot_army_rpg, :nats_publisher) end)
    end

    test "a party read that fails leaves the GM narrating, not the turn wordless" do
      stub_session()
      stub_table()

      stub(BotArmyRpg.PartyStoreMock, :get_party, fn _tenant, _user ->
        raise "the store is down"
      end)

      expect(BotArmyRpg.SceneFactStoreMock, :append, fn fact ->
        send(self(), {:appended, fact})
        {:ok, %{}}
      end)

      assert {:ok, result} =
               GMHandler.handle_action_resolve(
                 payload(%{
                   "character_id" => @character,
                   "action" => %{"action_type" => "inspect"}
                 })
               )

      assert_received {:appended, fact}
      assert fact["source"] == "gm"
      assert fact["content"] == result["narration"]
      assert result["narrator"] == nil
    end
  end
end
