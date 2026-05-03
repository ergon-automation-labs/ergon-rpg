defmodule BotArmyRpg do
  @moduledoc """
  The Resistance Chronicle — RPG bot for the Bot Army ecosystem.

  Manages character sheets, dice rolls, sessions, and scene facts
  for a TTRPG campaign system where real dev tasks are quests and
  bugs are goblin raids.
  """

  def version, do: Application.spec(:bot_army_rpg, :vsn) || "0.1.0"
end
