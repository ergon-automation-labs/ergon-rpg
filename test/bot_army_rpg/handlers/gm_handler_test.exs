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

  @tenant "00000000-0000-0000-0000-000000000001"
  @session "00000000-0000-0000-0000-0000000000se"
  @character "00000000-0000-0000-0000-0000000000ch"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
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
end
