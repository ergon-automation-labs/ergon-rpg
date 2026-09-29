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

  The happy paths that publish (`rpg.turn.your_turn` goes out through the Publisher) are
  not exercised here: the test run has no publisher by design, and a test that needs one
  would be testing the environment, not the handler.
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
end
