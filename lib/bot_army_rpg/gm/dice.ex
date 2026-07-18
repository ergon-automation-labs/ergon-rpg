defmodule BotArmyRpg.GM.Dice do
  @moduledoc """
  Thin wrapper for dice rolling in the GM engine.

  Prefers `bridge.random.roll` with fallback to local `DiceRoller`.
  """

  require Logger

  @bridge_timeout_ms 3000
  @circuit_breaker_key "rpg:gm:bridge.random.roll"

  @doc """
  Roll dice using the bridge-first pattern.

  Returns `{:ok, %{"total" => integer, "rolls" => [...]}}` or `{:error, reason}`.
  """
  def roll(notation) do
    roll(notation, publisher())
  end

  def roll(notation, publisher) do
    payload = %{"notation" => notation}

    case publisher.request("bridge.random.roll", payload,
           timeout_ms: @bridge_timeout_ms,
           circuit_breaker_key: @circuit_breaker_key
         ) do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _reason} ->
        Logger.warning(
          "[GM.Dice] bridge.random.roll unavailable, falling back to local DiceRoller"
        )

        BotArmyRpg.DiceRoller.roll(notation)
    end
  end

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end
end
