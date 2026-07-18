defmodule BotArmyRpg.PulsePublisher do
  @moduledoc """
  Periodic health pulse publisher for the RPG bot.

  Publishes domain-specific health metrics every 30 minutes to bot.rpg.pulse.
  """

  use GenServer
  require Logger

  @health_interval_ms 30 * 1000
  @publish_interval_ms 30 * 60 * 1000
  @service_name "rpg"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[PulsePublisher] Starting RPG bot pulse publisher")
    send(self(), :publish_pulse)
    Process.send_after(self(), :publish_health, 2_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:publish_health, state) do
    BotArmyLibraryRuntime.SynapseHealth.publish(
      source: "bot_army_rpg",
      service: @service_name,
      health_signal: health_signal()
    )

    Process.send_after(self(), :publish_health, @health_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_pulse, state) do
    Task.start(fn -> publish_pulse() end)
    Process.send_after(self(), :publish_pulse, @publish_interval_ms)
    {:noreply, state}
  end

  defp publish_pulse do
    signal = health_signal()

    pulse = %{
      service: @service_name,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      health: signal,
      metrics: %{}
    }

    case BotArmyLibraryRuntime.NATS.Publisher.publish("bot.#{@service_name}.pulse", pulse) do
      {:ok, _} ->
        Logger.debug("[PulsePublisher] Published pulse: #{signal}")

      {:error, reason} ->
        Logger.warning("[PulsePublisher] Failed to publish pulse: #{inspect(reason)}")
    end
  end

  defp health_signal do
    :nominal
  end
end
