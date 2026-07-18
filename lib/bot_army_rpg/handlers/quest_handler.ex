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
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    gtd_task = Map.get(params, "gtd_task", %{})
    source_category = Map.get(params, "source_category") || Map.get(gtd_task, "source_category")

    # Check recon gate: if category has pending recon task, block
    case check_recon_gate(source_category, tenant_id) do
      {:error, {:recon_required, task_id}} ->
        Logger.info(
          "[QuestHandler] Quest creation blocked: recon required for category #{source_category}"
        )

        {:error,
         %{
           "ok" => false,
           "reason" => "recon_required",
           "task_id" => task_id,
           "message" =>
             "Complete your reconnaissance task before starting a new mission in this category."
         }}

      :ok ->
        with {:ok, character} <- character_store().get_by_user_id(tenant_id, user_id),
             character_id <- character["id"] do
          quest = BotArmyRpg.QuestEngine.create_from_gtd_task(gtd_task)

          case quest_store().create(character_id, quest) do
            {:ok, created_quest} ->
              # Persist to DB
              persist_quest_to_db(created_quest, character_id, tenant_id, user_id)

              BotArmyRpg.NATS.Publisher.publish("rpg.quest.created", created_quest,
                tenant_id: tenant_id,
                user_id: user_id
              )

              {:ok, created_quest}

            {:error, reason} ->
              Logger.error("[QuestHandler] Create failed: #{inspect(reason)}")
              {:error, reason}
          end
        else
          {:error, _} ->
            Logger.error("[QuestHandler] Character not found for user")
            {:error, :character_not_found}
        end
    end
  end

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

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
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    quest_id = params["quest_id"]
    success_band = params["success_band"]
    dice_roll = params["dice_roll"]

    with {:ok, character} <- character_store().get_by_user_id(tenant_id, user_id),
         character_id <- character["id"],
         {:ok, quest} <- quest_store().get(character_id, quest_id),
         {:ok, success_band} <- derive_success_band(success_band, dice_roll, character) do
      opts = [success_band: success_band]
      completed_quest = BotArmyRpg.QuestEngine.mark_completed(quest, character["level"], opts)

      case quest_store().update(character_id, quest_id, completed_quest) do
        {:ok, updated_quest} ->
          # Persist completion to DB
          persist_quest_completion_to_db(quest_id, updated_quest)

          # Award XP with multiplier
          xp_reward = get_in(updated_quest, ["rewards_earned", "xp"]) || 100

          case character_store().award_xp(tenant_id, user_id, xp_reward) do
            {:ok, updated_char} ->
              BotArmyRpg.NATS.Publisher.publish("rpg.quest.completed", updated_quest,
                tenant_id: tenant_id,
                user_id: user_id,
                xp_awarded: xp_reward,
                character_level: updated_char["level"],
                success_band: success_band
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

  defp derive_success_band(nil, nil, _character) do
    {:ok, "full_success"}
  end

  defp derive_success_band(band, _dice_roll, _character) when is_binary(band) do
    {:ok, band}
  end

  defp derive_success_band(nil, dice_roll, _character) when is_map(dice_roll) do
    {:ok, Map.get(dice_roll, "success_band", "full_success")}
  end

  defp check_recon_gate(nil, _tenant_id) do
    :ok
  end

  defp check_recon_gate(source_category, tenant_id) when is_binary(source_category) do
    payload = %{
      "labels" => ["task_type:recon", "category:#{source_category}"],
      "status" => ["active", "next_action", "claimed"],
      "tenant_id" => tenant_id
    }

    case BotArmyLibraryRuntime.NATS.Publisher.request("bridge.task.list", payload, timeout_ms: 3000) do
      {:ok, %{"data" => tasks}} when is_list(tasks) and tasks != [] ->
        task = List.first(tasks)
        {:error, {:recon_required, Map.get(task, "id")}}

      {:ok, _} ->
        :ok

      :error ->
        Logger.warning("[QuestHandler] Recon gate check failed")
        :ok
    end
  rescue
    _ -> :ok
  end

  defp persist_quest_to_db(quest, character_id, tenant_id, user_id) do
    quest_attrs = %{
      "id" => Map.get(quest, "id"),
      "character_id" => character_id,
      "title" => Map.get(quest, "title"),
      "description" => Map.get(quest, "description"),
      "narrative_framing" => Map.get(quest, "narrative_framing"),
      "priority" => Map.get(quest, "priority", "normal"),
      "status" => Map.get(quest, "status", "active"),
      "progress" => Map.get(quest, "progress", %{}),
      "rewards" => Map.get(quest, "rewards", %{}),
      "linked_gtd_id" => Map.get(quest, "linked_gtd_id"),
      "source_category" => Map.get(quest, "source_category"),
      "tenant_id" => tenant_id,
      "user_id" => user_id
    }

    BotArmyRpg.Repo.insert(
      BotArmyRpg.Schemas.Quest.changeset(%BotArmyRpg.Schemas.Quest{}, quest_attrs),
      on_conflict: :nothing
    )
  rescue
    _ -> :ok
  end

  defp persist_quest_completion_to_db(quest_id, quest) do
    case BotArmyRpg.Repo.get(BotArmyRpg.Schemas.Quest, quest_id) do
      nil ->
        :ok

      db_quest ->
        updates = %{
          "status" => Map.get(quest, "status"),
          "success_band" => Map.get(quest, "success_band"),
          "outcome_score" => Map.get(quest, "outcome_score"),
          "dice_roll" => Map.get(quest, "dice_roll"),
          "rewards" => Map.get(quest, "rewards")
        }

        BotArmyRpg.Repo.update(BotArmyRpg.Schemas.Quest.changeset(db_quest, updates))
    end
  rescue
    _ -> :ok
  end
end
