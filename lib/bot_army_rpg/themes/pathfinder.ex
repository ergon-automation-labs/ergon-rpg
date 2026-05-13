defmodule BotArmyRpg.Themes.Pathfinder do
  @moduledoc """
  Pathfinder-style theme preset.

  Default fantasy chassis: d20 + stat modifier, ±10 critical bands, natural
  20 always crits. This is the same chassis the rules engine falls back to
  when a theme leaves `success_bands` blank, made explicit here so the
  registry has at least two presets and operators can choose the default
  by name rather than relying on emptiness.

  ## Notes

  This preset stays system-agnostic prose (no class-specific references).
  Bot archetypes use the existing canonical race/class assignments from
  `BotArmyRpg.Defaults`; flipping to this theme doesn't reskin anyone.
  """

  use BotArmyRpg.Themes.Preset

  @impl true
  def name, do: "pathfinder"

  @impl true
  def display_name, do: "Pathfinder-style Fantasy"

  @impl true
  def description do
    "Classic d20 fantasy chassis: ability modifiers, ±10 critical bands, natural 20 always crits. Generic high-fantasy flavor."
  end

  @impl true
  def theme do
    %{
      "setting" => "Pathfinder-style fantasy",
      "tone" => "heroic, slightly grim around the edges",
      "mechanic" => "d20 + stat modifier vs DC",
      "vocabulary" => %{
        "attack" => "strike",
        "defend" => "guard",
        "buff" => "bless",
        "inspire" => "rally",
        "inspect" => "perceive",
        "negotiate" => "parley",
        "hack" => "pick the lock",
        "evade" => "dodge",
        "skill" => "use a craft",
        "move" => "advance"
      },
      "templates" => %{
        "scene_intro" =>
          "Torchlight gutters along damp stone. Somewhere in the dark, water drips on iron.",
        "combat_intro" =>
          "Steel clears leather and the air sharpens. You have heartbeats, not minutes.",
        "rest_scene" =>
          "You camp by the road. The fire crackles. The hills lean close to listen.",
        "victory" =>
          "Silence returns to the field. Somewhere a horse stamps; somewhere blood drains into the earth.",
        "defeat" => "The line breaks. You fall back into the trees, faster than you would like."
      },
      "npc_personas" => %{
        "veteran_guard" => %{
          "title" => "Veteran Guard",
          "demeanor" => "tired, polite, has seen worse, wants to go home",
          "carries" => ["longsword", "shield", "horn"]
        },
        "court_mage" => %{
          "title" => "Court Mage",
          "demeanor" => "exact, formal, tolerates fools at a measured distance",
          "carries" => ["staff", "spellbook", "writ of council"]
        },
        "tavern_keeper" => %{
          "title" => "Tavern Keeper",
          "demeanor" => "warm to coin, warmer to news",
          "carries" => ["ledger", "rag", "trusted club beneath the bar"]
        }
      },
      "rules" => %{
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
          "dice" => "1d20",
          "success_bands" => [
            %{"name" => "critical_success", "type" => "eq_max", "value" => 20},
            %{"name" => "critical_success", "type" => "gte_dc_plus", "value" => 10},
            %{"name" => "success", "type" => "gte_dc", "value" => 0},
            %{"name" => "critical_failure", "type" => "lte_dc_minus", "value" => 10},
            %{"name" => "failure", "type" => "lt_dc", "value" => 0}
          ]
        }
      }
    }
  end
end
