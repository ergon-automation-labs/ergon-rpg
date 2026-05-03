defmodule BotArmyRpg.Defaults do
  @moduledoc """
  Default character sheet templates.

  Pathfinder-compatible defaults that serve as initial values
  when creating a new character. The schema stores stats as jsonb,
  so any TTRPG system can be represented.
  """

  @doc """
  Returns a Pathfinder-compatible default character sheet.

  This is a template/initial value, NOT a schema constraint.
  The stats field in the database is jsonb and can hold any structure.
  """
  def default_pathfinder_stats do
    %{
      "ability_scores" => %{
        "str" => 10,
        "dex" => 10,
        "con" => 10,
        "int" => 10,
        "wis" => 10,
        "cha" => 10
      },
      "hp" => %{"current" => 10, "max" => 10, "temp" => 0},
      "ac" => 10,
      "saves" => %{"fort" => 0, "reflex" => 0, "will" => 0},
      "skills" => %{},
      "attacks" => [],
      "features" => [],
      "spells" => %{}
    }
  end

  @doc """
  Returns an empty inventory template.
  """
  def default_inventory do
    %{
      "equipment" => [],
      "gold" => 0,
      "items" => []
    }
  end
end
