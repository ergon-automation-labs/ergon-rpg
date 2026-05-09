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

  @reconnect_delay_ms 5_000

  @subjects [
    "events.gtd.task.completed",
    "events.fitness.workout.completed",
    "events.learning.lesson.completed"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: [], conn: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()

        Logger.info(
          "[ProgressionSubscriber] Connected to NATS, subscribing to progression events"
        )

        subscriptions =
          @subjects
          |> Enum.map(fn subject ->
            case Gnat.sub(conn, self(), subject) do
              {:ok, sub} ->
                Logger.info("[ProgressionSubscriber] Subscribed to #{subject}")
                sub

              {:error, reason} ->
                Logger.error(
                  "[ProgressionSubscriber] Failed to subscribe to #{subject}: #{inspect(reason)}"
                )

                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

      {:error, _reason} ->
        Logger.warning("[ProgressionSubscriber] NATS connection not ready, will retry")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    Logger.debug("[ProgressionSubscriber] Received on #{msg.topic}")

    with {:ok, decoded} <- BotArmyCore.NATS.Decoder.decode(msg.body),
         tenant_id <- Map.get(decoded, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id(),
         {:ok, xp_amount, loot_source} <- event_to_xp(msg.topic, decoded) do
      handle_progression(tenant_id, decoded, xp_amount, loot_source)
    else
      {:error, reason} ->
        Logger.debug("[ProgressionSubscriber] Skipped #{msg.topic}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[ProgressionSubscriber] Disconnected from NATS, will reconnect")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: [], conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[ProgressionSubscriber] Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
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

  defp event_to_xp("events.fitness.workout.completed", event) do
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
      case CharacterStore.award_xp(tenant_id, user_id, xp_amount) do
        {:ok, character} ->
          # Generate and award loot
          priority = Map.get(event, "priority") || Map.get(event, "intensity") || "normal"
          loot = LootEngine.generate(loot_source, priority)

          if loot do
            CharacterStore.add_item(tenant_id, user_id, loot)
          end

          Logger.info(
            "[ProgressionSubscriber] #{xp_amount} XP awarded to #{user_id}, new level: #{character["level"]}"
          )

        {:error, reason} ->
          Logger.warning(
            "[ProgressionSubscriber] Failed to award XP to #{user_id}: #{inspect(reason)}"
          )
      end
    else
      Logger.debug("[ProgressionSubscriber] Event missing user_id, skipping")
    end
  end
end
