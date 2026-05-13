defmodule BotArmyRpg.Themes.IronKingdoms do
  @moduledoc """
  Iron Kingdoms theme preset — narration-only.

  Reskins the GM's prose with the language of full-metal fantasy: coal smoke,
  arcane mechanika, steamjacks, warcasters, and the warring nations of
  western Immoren. The bot's mechanical chassis (d20-ish resolution, stat
  modifiers, ±10 critical bands) stays unchanged, so existing characters and
  rules paths work without migration.

  ## What this theme touches

    * `setting` / `tone` — flavors the LLM prompt frame in
      `BotArmyRpg.GM.Narrator`.
    * `vocabulary` — string substitutions the narrator weaves into both LLM
      prompts and the fallback verb picker in `Narrator.fallback_action/3`.
    * `templates` — short scene snippets a caller can splice into intros and
      rest/victory/defeat beats.
    * `npc_personas` — faction archetypes for spawn helpers and prompt hints.
      Each persona may declare a `"bot_assignments"` list naming which bot
      IDs it reskins (resolved by `BotArmyRpg.Themes.Archetype`). This is
      narration-only — character rows are untouched, so flipping themes
      back to default does not lie about race/class on the sheet.
    * `rules` — declares the action types and the 2d6 + ±4 resolution
      chassis. `BotArmyRpg.GM.RulesEngine.resolve_outcome/3` walks the
      `success_bands` list in order; the first match wins.

  ## Attribution

  Inspired by Privateer Press's Iron Kingdoms setting. All prose in this
  module is original; no copyrighted text is reproduced. Faction and
  archetype names are setting references, not rule quotations.
  """

  use BotArmyRpg.Themes.Preset

  @impl true
  def name, do: "iron_kingdoms"

  @impl true
  def display_name, do: "Iron Kingdoms"

  @impl true
  def description do
    "Grim industrial fantasy — coal smoke, arcane oil, and steamjacks under the gaslights of Caspia and Korsk. Narration-only skin; mechanics inherit the bot's current chassis."
  end

  @impl true
  @doc """
  Returns the canonical Iron Kingdoms theme map, shaped for
  `BotArmyRpg.ThemeStore.set_current/3`.
  """
  def theme do
    %{
      "setting" => "Iron Kingdoms",
      "tone" => "grim industrial fantasy — coal smoke, arcane oil, and old gods",
      "mechanic" => "warjack-era adventuring",
      "vocabulary" => vocabulary(),
      "templates" => templates(),
      "npc_personas" => npc_personas(),
      "rules" => rules()
    }
  end

  defp vocabulary do
    %{
      "attack" => "barrage",
      "defend" => "brace behind plate",
      "buff" => "anoint with reagents",
      "inspire" => "rally the column",
      "inspect" => "scry the workings",
      "negotiate" => "parley",
      "hack" => "splice the arc node",
      "evade" => "duck the smokestack",
      "skill" => "exercise the trade",
      "move" => "advance",
      "spell" => "rune-bound invocation",
      "wizard" => "arcane mechanik",
      "priest" => "warcaster of the faith",
      "knight" => "trencher",
      "soldier" => "ironclad",
      "guard" => "city watch in greatcoats",
      "city" => "industrial city",
      "town" => "steam-lit settlement",
      "tavern" => "tap house",
      "inn" => "guildhouse lodgings",
      "horse" => "horse or light warjack",
      "carriage" => "steam carriage",
      "ship" => "iron-prowed steamer",
      "forest" => "blighted woods",
      "mountain" => "ridge of slag and stone",
      "magic" => "mechanika",
      "weapon" => "rifle, mace, or warjack fist",
      "armor" => "trencher plate",
      "gold" => "gold crowns"
    }
  end

  defp templates do
    %{
      "scene_intro" =>
        "Coal-smoke hangs over the cobbles; a distant warjack heaves through the fog and the streetlamps gutter as a column of light marches by.",
      "combat_intro" =>
        "Steam vents hiss, hammers ring against riveted plate, and the air smells of cordite and arcane oil.",
      "rest_scene" =>
        "You camp beneath a sagging awning. A coal stove ticks. Somewhere across the rooflines, a foundry roars through the night.",
      "victory" =>
        "The smokestacks fall silent. Cooling iron pings in the quiet, and the smell of cordite begins to clear.",
      "defeat" =>
        "The boilers go cold. Steam bleeds from a cracked manifold and your column staggers back into the smoke."
    }
  end

  defp npc_personas do
    %{
      "gun_mage" => %{
        "title" => "Gun Mage",
        "demeanor" => "cool, theatrical, and dangerous at fifty paces",
        "carries" => ["magelock pistol", "rune-etched gauntlet"],
        "bot_assignments" => ["discord"]
      },
      "trencher" => %{
        "title" => "Trencher Sergeant",
        "demeanor" => "blunt, soot-stained, loyal to the squad first and the crown second",
        "carries" => ["military rifle", "trench knife", "field whistle"],
        "bot_assignments" => ["sre"]
      },
      "arcane_mechanik" => %{
        "title" => "Arcane Mechanik",
        "demeanor" => "harried, ink-stained, talks to her warjack like it is a stubborn dog",
        "carries" => ["spanner-wand", "rune dies", "spare accumulator"],
        "bot_assignments" => ["llm", "claude_bridge"]
      },
      "warcaster" => %{
        "title" => "Warcaster",
        "demeanor" => "imperious, weighted by command, every word measured",
        "carries" => ["mechanika armor", "warjack control link"],
        "bot_assignments" => ["fitness"]
      },
      "gobber_tinker" => %{
        "title" => "Gobber Tinker",
        "demeanor" => "fast-talking, opportunistic, suspiciously well-supplied",
        "carries" => ["satchel of springs", "questionable elixirs"],
        "bot_assignments" => ["gtd"]
      },
      "menite_scrutator" => %{
        "title" => "Menite Scrutator",
        "demeanor" => "righteous, austere, asks the questions you do not want asked",
        "carries" => ["censer", "writ of inquiry"],
        "bot_assignments" => ["terrain"]
      },
      "cryxian_necrotech" => %{
        "title" => "Cryxian Necrotech",
        "demeanor" => "gleeful in a way that suggests recent grave-robbing",
        "carries" => ["bone saw", "vials of necrotite"],
        "bot_assignments" => ["database_backups"]
      },
      "merchant_prince" => %{
        "title" => "Mercaran Merchant Prince",
        "demeanor" => "silken, contractually precise, always two ledgers ahead",
        "carries" => ["sealed writs", "ornamented pistol", "bonded clerk"],
        "bot_assignments" => ["chore", "job_applications"]
      },
      "iosan_envoy" => %{
        "title" => "Iosan Envoy",
        "demeanor" => "remote, exacting, speaks of human matters as weather",
        "carries" => ["fellblade", "diplomatic seal"],
        "bot_assignments" => ["synapse"]
      }
    }
  end

  defp rules do
    %{
      "action_types" => [
        "attack",
        "defend",
        "buff",
        "inspire",
        "inspect",
        "negotiate",
        "hack",
        "evade",
        "skill",
        "move"
      ],
      "resolution" => %{
        "dice" => "2d6",
        "success_bands" => [
          %{"name" => "critical_success", "type" => "gte_dc_plus", "value" => 4},
          %{"name" => "success", "type" => "gte_dc", "value" => 0},
          %{"name" => "critical_failure", "type" => "lte_dc_minus", "value" => 4},
          %{"name" => "failure", "type" => "lt_dc", "value" => 0}
        ]
      }
    }
  end
end
