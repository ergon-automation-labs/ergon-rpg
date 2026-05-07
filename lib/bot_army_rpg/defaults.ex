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

  @doc """
  Returns bot-specific default archetypes keyed by bot_id string.
  """
  def bot_archetypes do
    %{
      "gtd" => %{race: "Human", class: "Scheduler"},
      "gtd_bot" => %{race: "Human", class: "Scheduler"},
      "bot_army_gtd" => %{race: "Human", class: "Scheduler"},
      "synapse" => %{race: "Elf", class: "Oracle"},
      "bot_army_synapse" => %{race: "Elf", class: "Oracle"},
      "llm" => %{race: "Tiefling", class: "Bard"},
      "llm_bot" => %{race: "Tiefling", class: "Bard"},
      "bot_army_llm" => %{race: "Tiefling", class: "Bard"},
      "sre" => %{race: "Dwarf", class: "Sentinel"},
      "sre_terminal" => %{race: "Dwarf", class: "Sentinel"},
      "bot_army_sre" => %{race: "Dwarf", class: "Sentinel"},
      "fitness" => %{race: "Half-Orc", class: "Drillmaster"},
      "fitness_bot" => %{race: "Half-Orc", class: "Drillmaster"},
      "bot_army_fitness" => %{race: "Half-Orc", class: "Drillmaster"},
      "terrain" => %{race: "Changeling", class: "Shapeshifter"},
      "terrain_bot" => %{race: "Changeling", class: "Shapeshifter"},
      "bot_army_terrain" => %{race: "Changeling", class: "Shapeshifter"},
      "chore" => %{race: "Halfling", class: "Steward"},
      "chore_bot" => %{race: "Halfling", class: "Steward"},
      "bot_army_chore" => %{race: "Halfling", class: "Steward"},
      "job_applications" => %{race: "Human", class: "Fixer"},
      "job_bot" => %{race: "Human", class: "Fixer"},
      "bot_army_job_applications" => %{race: "Human", class: "Fixer"},
      "discord" => %{race: "Human", class: "Herald"},
      "discord_bot" => %{race: "Human", class: "Herald"},
      "bot_army_discord" => %{race: "Human", class: "Herald"},
      "claude_bridge" => %{race: "Gnome", class: "Scribe"},
      "bridge_bot" => %{race: "Gnome", class: "Scribe"},
      "bot_army_claude_bridge" => %{race: "Gnome", class: "Scribe"},
      "database_backups" => %{race: "Dwarf", class: "Archivist"},
      "backups_bot" => %{race: "Dwarf", class: "Archivist"},
      "bot_army_database_backups" => %{race: "Dwarf", class: "Archivist"}
    }
  end

  @doc """
  Returns default archetype for a bot_id, falling back to generic Adventurer.
  """
  def bot_archetype(bot_id) when is_binary(bot_id) do
    key =
      bot_id
      |> String.downcase()
      |> String.replace_prefix("bot_army_", "")

    Map.get(bot_archetypes(), key, %{race: "Unknown", class: "Adventurer"})
  end

  def bot_archetype(bot_id) when is_atom(bot_id) do
    bot_id
    |> Atom.to_string()
    |> bot_archetype()
  end

  def bot_archetype(_), do: %{race: "Unknown", class: "Adventurer"}

  @doc """
  Returns default play_style heuristic per class.
  Used by GM.BotPlayer to pick actions.
  """
  def class_play_styles do
    %{
      "Scheduler" => %{primary: "buff", secondary: "skill", tertiary: "attack"},
      "Oracle" => %{primary: "inspect", secondary: "skill", tertiary: "defend"},
      "Bard" => %{primary: "inspire", secondary: "negotiate", tertiary: "attack"},
      "Sentinel" => %{primary: "defend", secondary: "attack", tertiary: "inspect"},
      "Drillmaster" => %{primary: "attack", secondary: "defend", tertiary: "move"},
      "Shapeshifter" => %{primary: "evade", secondary: "skill", tertiary: "attack"},
      "Steward" => %{primary: "defend", secondary: "buff", tertiary: "skill"},
      "Fixer" => %{primary: "negotiate", secondary: "hack", tertiary: "attack"},
      "Herald" => %{primary: "inspire", secondary: "inspect", tertiary: "negotiate"},
      "Scribe" => %{primary: "inspect", secondary: "skill", tertiary: "defend"},
      "Archivist" => %{primary: "inspect", secondary: "defend", tertiary: "skill"},
      "Adventurer" => %{primary: "attack", secondary: "skill", tertiary: "defend"}
    }
  end

  @doc """
  Default cyberpunk stat block (system-agnostic jsonb).
  """
  def default_cyberpunk_stats do
    %{
      "ability_scores" => %{
        "net" => 10,
        "cool" => 10,
        "tech" => 10,
        "body" => 10,
        "ref" => 10,
        "emp" => 10
      },
      "hp" => %{"current" => 20, "max" => 20, "temp" => 0},
      "ac" => 10,
      "saves" => %{"fort" => 0, "reflex" => 0, "will" => 0},
      "skills" => %{},
      "attacks" => [],
      "features" => [],
      "spells" => %{}
    }
  end
end
