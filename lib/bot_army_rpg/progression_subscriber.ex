defmodule BotArmyRpg.ProgressionSubscriber do
  @moduledoc """
  Converts cross-bot events (GTD tasks, fitness workouts, learning lessons) into character progression.

  Subscribes to real-world events from other bots and awards XP to characters, generates loot,
  handles level-ups. This is how the RPG character grows with actual productivity and health.
  """

  use GenServer
  require Logger

  alias BotArmyRpg.CharacterStore
  alias BotArmyRpg.LootEngine
  alias BotArmyRpg.Progression.Companions

  @subjects [
    "events.gtd.task.created",
    "events.gtd.task.completed",
    "events.fitness.workout.logged",
    "events.learning.lesson.completed"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    # Declared once and held by the Connection, which re-subscribes this exact list
    # on every link it starts. The old per-subject `Gnat.sub/3` on each
    # `{:nats, :connected}` added a fresh subscription per flap — measured live
    # 2026-10-13: the air<->mini leaf had flapped 8 times, multiplying every
    # progression subject, so a single `events.gtd.task.completed` ran this handler
    # over and over and awarded its XP over and over. `Registry.register/3` replaces
    # rather than appends, so one event now costs one award.
    :ok = BotArmyLibraryRuntime.NATS.Connection.subscribe(@subjects)

    Logger.info(
      "[ProgressionSubscriber] Subscribing to #{length(@subjects)} progression event subjects"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    Logger.debug("[ProgressionSubscriber] Received on #{msg.topic}")

    case BotArmyLibraryCore.NATS.Decoder.decode(msg.body) do
      {:ok, decoded} ->
        tenant_id =
          Map.get(decoded, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()

        case msg.topic do
          "events.gtd.task.created" ->
            handle_quest_creation(tenant_id, decoded)

          _ ->
            case event_to_xp(msg.topic, decoded) do
              {:ok, xp_amount, loot_source} ->
                handle_progression(tenant_id, decoded, xp_amount, loot_source)

              {:error, reason} ->
                Logger.debug("[ProgressionSubscriber] Skipped #{msg.topic}: #{inspect(reason)}")
            end
        end

      {:error, reason} ->
        Logger.debug("[ProgressionSubscriber] Decode failed #{msg.topic}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Event → XP mapping
  defp event_to_xp("events.gtd.task.completed", event) do
    priority = Map.get(event, "priority", "normal")
    xp = priority_xp(priority)
    {:ok, xp, "gtd_task"}
  end

  defp event_to_xp("events.fitness.workout.logged", event) do
    intensity = Map.get(event, "intensity", "moderate")
    xp = intensity_xp(intensity)
    {:ok, xp, "fitness_workout"}
  end

  defp event_to_xp("events.learning.lesson.completed", event) do
    difficulty = Map.get(event, "difficulty", "intermediate")
    xp = difficulty_xp(difficulty)
    {:ok, xp, "learning_lesson"}
  end

  defp event_to_xp(topic, _event) do
    {:error, {:unknown_topic, topic}}
  end

  defp priority_xp("high"), do: 200
  defp priority_xp("urgent"), do: 250
  defp priority_xp("normal"), do: 100
  defp priority_xp("low"), do: 50
  defp priority_xp(_), do: 100

  defp intensity_xp("high"), do: 200
  defp intensity_xp("moderate"), do: 100
  defp intensity_xp("low"), do: 50
  defp intensity_xp(_), do: 100

  defp difficulty_xp("advanced"), do: 300
  defp difficulty_xp("intermediate"), do: 150
  defp difficulty_xp("beginner"), do: 75
  defp difficulty_xp(_), do: 100

  # Award XP and generate loot
  defp handle_progression(tenant_id, event, xp_amount, loot_source) do
    user_id = Map.get(event, "user_id")

    if user_id do
      # Snapshot level before awarding XP to detect level-ups
      old_level = get_character_level(tenant_id, user_id)

      case CharacterStore.award_xp(tenant_id, user_id, xp_amount) do
        {:ok, character} ->
          new_level = character["level"]
          leveled_up = new_level > old_level

          # Generate and award loot
          priority = Map.get(event, "priority") || Map.get(event, "intensity") || "normal"
          loot = LootEngine.generate(loot_source, priority)

          if loot do
            CharacterStore.add_item(tenant_id, user_id, loot)
          end

          # Auto-complete matching quest if this was a task completion
          task_id = Map.get(event, "task_id")
          quest_bonus = maybe_complete_quest(tenant_id, user_id, character, task_id)

          # Publish progression notification for Discord/surfaces
          publish_progression_notification(
            tenant_id,
            user_id,
            character,
            xp_amount,
            leveled_up,
            old_level,
            loot,
            quest_bonus
          )

          Logger.info(
            "[ProgressionSubscriber] #{xp_amount} XP awarded to #{user_id}, level #{new_level}#{if leveled_up, do: " (LEVEL UP!)", else: ""}#{if quest_bonus, do: " + quest bonus #{quest_bonus} XP", else: ""}"
          )

          # The other track: the household keeps growing while this character is away, at a
          # reduced share of the award above. It cannot touch that award - see Companions.
          Companions.award_away(tenant_id, character, xp_amount)

        {:error, reason} ->
          Logger.warning(
            "[ProgressionSubscriber] Failed to award XP to #{user_id}: #{inspect(reason)}"
          )
      end
    else
      Logger.debug("[ProgressionSubscriber] Event missing user_id, skipping")
    end
  end

  defp get_character_level(tenant_id, user_id) do
    case CharacterStore.get_by_user_id(tenant_id, user_id) do
      {:ok, char} -> Map.get(char, "level", 1)
      _ -> 1
    end
  end

  defp maybe_complete_quest(tenant_id, user_id, character, task_id)
       when is_binary(task_id) do
    character_id = character["id"]
    quest_store = Application.get_env(:bot_army_rpg, :quest_store, BotArmyRpg.QuestStore)

    case quest_store.find_by_gtd_id(character_id, task_id) do
      {:ok, quest} ->
        completed = BotArmyRpg.QuestEngine.mark_completed(quest, character["level"])

        case quest_store.update(character_id, quest["id"], completed) do
          {:ok, updated_quest} ->
            bonus_xp = get_in(updated_quest, ["rewards_earned", "xp"]) || 0

            if bonus_xp > 0 do
              CharacterStore.award_xp(tenant_id, user_id, bonus_xp)
            end

            BotArmyRpg.NATS.Publisher.publish("rpg.quest.completed", updated_quest,
              tenant_id: tenant_id,
              user_id: user_id
            )

            Logger.info(
              "[ProgressionSubscriber] Quest completed: \"#{quest["title"]}\" +#{bonus_xp} bonus XP"
            )

            bonus_xp

          {:error, reason} ->
            Logger.warning("[ProgressionSubscriber] Quest update failed: #{inspect(reason)}")
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp maybe_complete_quest(_tenant_id, _user_id, _character, _task_id), do: nil

  defp publish_progression_notification(
         tenant_id,
         user_id,
         character,
         xp_amount,
         leveled_up,
         old_level,
         loot,
         quest_bonus
       ) do
    stats = Map.get(character, "stats", %{})

    notification = %{
      "character_name" => character["name"],
      "xp_earned" => xp_amount,
      "xp_current" => Map.get(stats, "xp", 0),
      "xp_to_next" => Map.get(stats, "xp_to_next", 500),
      "level" => character["level"],
      "leveled_up" => leveled_up,
      "old_level" => old_level,
      "loot" => loot,
      "quest_bonus_xp" => quest_bonus
    }

    BotArmyRpg.NATS.Publisher.publish("rpg.progression.awarded", notification,
      tenant_id: tenant_id,
      user_id: user_id
    )

    if leveled_up do
      BotArmyRpg.NATS.Publisher.publish(
        "rpg.character.leveled_up",
        %{
          "character_name" => character["name"],
          "old_level" => old_level,
          "new_level" => character["level"],
          "class" => character["class"]
        },
        tenant_id: tenant_id,
        user_id: user_id
      )
    end
  end

  # Auto-create RPG quest from GTD task
  defp handle_quest_creation(tenant_id, event) do
    user_id = Map.get(event, "user_id")
    task_title = Map.get(event, "task_title", "")
    task_id = Map.get(event, "task_id")
    priority = Map.get(event, "priority", "normal")

    if user_id && task_title != "" do
      case CharacterStore.get_by_user_id(tenant_id, user_id) do
        {:ok, character} ->
          character_id = character["id"]

          gtd_task = %{
            "title" => task_title,
            "priority" => priority,
            "id" => task_id
          }

          quest = BotArmyRpg.QuestEngine.create_from_gtd_task(gtd_task)

          quest_store = Application.get_env(:bot_army_rpg, :quest_store, BotArmyRpg.QuestStore)

          case quest_store.create(character_id, quest) do
            {:ok, created_quest} ->
              BotArmyRpg.NATS.Publisher.publish("rpg.quest.created", created_quest,
                tenant_id: tenant_id,
                user_id: user_id
              )

              Logger.info(
                "[ProgressionSubscriber] Quest auto-created: \"#{quest["title"]}\" for #{user_id}"
              )

            {:error, reason} ->
              Logger.warning("[ProgressionSubscriber] Quest creation failed: #{inspect(reason)}")
          end

        {:error, _} ->
          Logger.debug("[ProgressionSubscriber] No character for #{user_id}, skipping quest")
      end
    else
      Logger.debug("[ProgressionSubscriber] Task event missing user_id or title, skipping quest")
    end
  end
end
