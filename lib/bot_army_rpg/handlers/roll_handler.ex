defmodule BotArmyRpg.Handlers.RollHandler do
  require Logger

  def handle_roll(message) do
    params = message["payload"] || message
    notation = params["notation"]

    if is_nil(notation) or notation == "" do
      {:error, :notation_required}
    else
      case BotArmyRpg.DiceRoller.roll(notation) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          Logger.warning("[RollHandler] Invalid dice notation '#{notation}': #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
