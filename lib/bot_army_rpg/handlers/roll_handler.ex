defmodule BotArmyRpg.Handlers.RollHandler do
  @moduledoc "Handles NATS requests for dice rolls and skill checks."
  require Logger

  @bridge_timeout_ms 2000

  def handle_roll(message) do
    handle_roll(message, publisher())
  end

  def handle_roll(message, publisher) do
    params = message["payload"] || message
    notation = params["notation"]
    seed = params["seed"]

    if is_nil(notation) or notation == "" do
      {:error, :notation_required}
    else
      roll_via_bridge(notation, seed, publisher)
    end
  end

  defp roll_via_bridge(notation, seed, publisher) do
    payload = %{"notation" => notation}
    payload = if seed && seed != "", do: Map.put(payload, "seed", seed), else: payload

    case publisher.request("bridge.random.roll", payload,
           timeout_ms: @bridge_timeout_ms,
           circuit_breaker_key: "rpg:bridge.random.roll"
         ) do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _reason} ->
        Logger.warning(
          "[RollHandler] bridge.random.roll unavailable, falling back to local DiceRoller"
        )

        BotArmyRpg.DiceRoller.roll(notation)
    end
  end

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end
end
