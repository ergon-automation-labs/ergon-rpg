defmodule BotArmyRpg.Handlers.QuestHandler do
  @moduledoc """
  Handles quest creation, progress, and completion.

  Quest lifecycle:
  1. Create from GTD task (rpg.quest.create)
  2. Progress as task completes (rpg.quest.progress)
  3. Complete and award XP multiplier (rpg.quest.complete)
  """

  require Logger

  defp quest_store do
    Application.get_env(:bot_army_rpg, :quest_store, BotArmyRpg.QuestStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_create(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)

    # Get character for user
    case character_store().get_by_user_id(tenant_id, user_id) do
      {:ok, character} ->
        character_id = character["id"]
        gtd_task = Map.get(params, "gtd_task", %{})

        quest = BotArmyRpg.QuestEngine.create_from_gtd_task(gtd_task)

        case quest_store().create(character_id, quest) do
          {:ok, created_quest} ->
            BotArmyRpg.NATS.Publisher.publish("rpg.quest.created", created_quest,
              tenant_id: tenant_id,
              user_id: user_id
            )

            {:ok, created_quest}

          {:error, reason} ->
            Logger.error("[QuestHandler] Create failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, _} ->
        Logger.error("[QuestHandler] Character not found for user")
        {:error, :character_not_found}
    end
  end

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)

    case character_store().get_by_user_id(tenant_id, user_id) do
      {:ok, character} ->
        character_id = character["id"]
        include_completed = Map.get(params, "include_completed", false)

        quests =
          if include_completed do
            {:ok, quests} = quest_store().list_all(character_id)
            quests
          else
            {:ok, quests} = quest_store().list_active(character_id)
            quests
          end

        {:ok, quests}

      {:error, _} ->
        {:error, :character_not_found}
    end
  end

  def handle_complete(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    quest_id = params["quest_id"]

    with {:ok, character} <- character_store().get_by_user_id(tenant_id, user_id),
         character_id <- character["id"],
         {:ok, quest} <- quest_store().get(character_id, quest_id) do
      completed_quest = BotArmyRpg.QuestEngine.mark_completed(quest, character["level"])

      case quest_store().update(character_id, quest_id, completed_quest) do
        {:ok, updated_quest} ->
          # Award XP with multiplier
          xp_reward = get_in(updated_quest, ["rewards_earned", "xp"]) || 100

          case character_store().award_xp(tenant_id, user_id, xp_reward) do
            {:ok, updated_char} ->
              BotArmyRpg.NATS.Publisher.publish("rpg.quest.completed", updated_quest,
                tenant_id: tenant_id,
                user_id: user_id,
                xp_awarded: xp_reward
              )

              {:ok, updated_quest}

            error ->
              error
          end

        error ->
          error
      end
    else
      {:error, reason} ->
        Logger.error("[QuestHandler] Complete failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
