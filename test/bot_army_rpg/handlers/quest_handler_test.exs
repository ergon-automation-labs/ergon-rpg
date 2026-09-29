defmodule BotArmyRpg.Handlers.QuestHandlerTest do
  @moduledoc """
  The quest log has to survive a store that cannot answer.

  `rpg.quest.list` used to read `{:ok, quests} = quest_store().list_active(character_id)` —
  a hard match — so a store error became a MatchError inside the handler. A raise in a
  handler kills the Consumer, which means every route in the bot goes silent until restart,
  not just this one. The first test here is the guard on that repair.

  The rest pins the reachable parts of the lifecycle, including one wrinkle worth naming:
  XP is awarded *after* the quest has already been marked complete, so a failed award leaves
  a completed quest behind and only the caller hears about it.
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.QuestHandler

  @tenant "00000000-0000-0000-0000-000000000001"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :quest_store, BotArmyRpg.QuestStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :quest_store)
      Application.delete_env(:bot_army_rpg, :character_store)
    end)

    :ok
  end

  defp payload(extra \\ %{}),
    do: Map.merge(%{"tenant_id" => @tenant, "user_id" => "someone"}, extra)

  defp a_character, do: {:ok, %{"id" => "character-1", "level" => 3}}

  describe "rpg.quest.list" do
    test "a store that could not answer is a refusal, never a MatchError" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)

      expect(BotArmyRpg.QuestStoreMock, :list_active, fn "character-1" -> {:error, :not_found} end)

      assert {:error, :not_found} = QuestHandler.handle_list(payload())
    end

    test "the active quests are returned when the store answers" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)

      expect(BotArmyRpg.QuestStoreMock, :list_active, fn "character-1" ->
        {:ok, [%{"id" => "q1", "title" => "Clean the hall"}]}
      end)

      assert {:ok, [%{"title" => "Clean the hall"}]} = QuestHandler.handle_list(payload())
    end

    test "include_completed asks the other question" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)

      expect(BotArmyRpg.QuestStoreMock, :list_all, fn "character-1" ->
        {:ok, [%{"id" => "q0", "status" => "completed"}]}
      end)

      assert {:ok, [%{"status" => "completed"}]} =
               QuestHandler.handle_list(payload(%{"include_completed" => true}))
    end

    test "no character means no quest log" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> {:error, :not_found} end)

      assert {:error, :character_not_found} = QuestHandler.handle_list(payload())
    end
  end

  describe "rpg.quest.create" do
    test "a caller with no character is refused" do
      # No source_category, so the recon gate is not consulted (that path asks the GTD
      # bridge) — the character lookup is the first and only thing this needs.
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> {:error, :not_found} end)

      assert {:error, :character_not_found} = QuestHandler.handle_create(payload())
    end
  end

  describe "rpg.quest.complete" do
    test "a caller with no character is refused — with the sibling route's other word for it" do
      # Measured asymmetry, pinned so it stays a decision instead of an accident: list and
      # create map a missing character to `:character_not_found`, while complete lets the
      # store's own `:not_found` through unchanged. Same condition, two vocabularies.
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> {:error, :not_found} end)

      assert {:error, :not_found} = QuestHandler.handle_complete(payload(%{"quest_id" => "q1"}))
      assert {:error, :character_not_found} = QuestHandler.handle_list(payload())
      assert {:error, :character_not_found} = QuestHandler.handle_create(payload())
    end

    test "a quest that is not in the log is refused" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)
      stub(BotArmyRpg.QuestStoreMock, :get, fn "character-1", "q1" -> {:error, :not_found} end)

      assert {:error, :not_found} = QuestHandler.handle_complete(payload(%{"quest_id" => "q1"}))
    end

    test "no band and no dice is full success, and the store is the one who sees it" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)

      stub(BotArmyRpg.QuestStoreMock, :get, fn "character-1", "q1" ->
        {:ok, %{"id" => "q1", "title" => "Clean the hall"}}
      end)

      expect(BotArmyRpg.QuestStoreMock, :update, fn "character-1", "q1", updated ->
        send(self(), {:marked, updated})
        # Stop here: the publish path must not be reached by a test.
        {:error, :stop_here}
      end)

      assert {:error, :stop_here} = QuestHandler.handle_complete(payload(%{"quest_id" => "q1"}))
      assert_received {:marked, updated}
      assert updated["success_band"] == "full_success"
    end

    test "an explicit band is honoured over the default" do
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)

      stub(BotArmyRpg.QuestStoreMock, :get, fn "character-1", "q1" ->
        {:ok, %{"id" => "q1"}}
      end)

      expect(BotArmyRpg.QuestStoreMock, :update, fn _c, _q, updated ->
        send(self(), {:marked, updated})
        {:error, :stop_here}
      end)

      assert {:error, :stop_here} =
               QuestHandler.handle_complete(
                 payload(%{"quest_id" => "q1", "success_band" => "partial_success"})
               )

      assert_received {:marked, updated}
      assert updated["success_band"] == "partial_success"
    end

    test "a failed XP award is reported, though the quest is already complete" do
      # The wrinkle, pinned: the quest was marked complete and persisted before the award
      # was attempted, so the caller's error does not undo the completion.
      stub(BotArmyRpg.CharacterStoreMock, :get_by_user_id, fn _t, _u -> a_character() end)
      stub(BotArmyRpg.QuestStoreMock, :get, fn "character-1", "q1" -> {:ok, %{"id" => "q1"}} end)

      expect(BotArmyRpg.QuestStoreMock, :update, fn _c, _q, _updated ->
        send(self(), :completed_before_the_award)
        {:ok, %{"id" => "q1", "rewards_earned" => %{"xp" => 100}}}
      end)

      stub(BotArmyRpg.CharacterStoreMock, :award_xp, fn _t, _u, 100 ->
        {:error, :xp_award_failed}
      end)

      assert {:error, :xp_award_failed} =
               QuestHandler.handle_complete(payload(%{"quest_id" => "q1"}))

      assert_received :completed_before_the_award
    end
  end
end
