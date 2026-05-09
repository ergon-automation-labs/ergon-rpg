defmodule BotArmyRpg.Handlers.LootHandler do
  @moduledoc """
  Handler for rpg.loot.generate NATS subject.
  """

  require Logger

  alias BotArmyRpg.LootEngine

  def handle_generate(message) do
    params = message["payload"] || message

    source = Map.get(params, "source", "gtd_task")
    priority = Map.get(params, "priority", "normal")

    case LootEngine.generate(source, priority) do
      nil ->
        {:error, :loot_generation_failed}

      loot ->
        {:ok, loot}
    end
  end
end
