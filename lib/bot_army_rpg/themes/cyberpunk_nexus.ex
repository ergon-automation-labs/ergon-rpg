defmodule BotArmyRpg.Themes.CyberpunkNexus do
  @moduledoc """
  Cyberpunk Nexus theme — Cyberpunk Red + Deus Ex fusion.

  A neon-soaked dystopia where mega-corporations rule through surveillance,
  augmentation, and conspiracy. Borrows Night City's street culture, netrunning,
  and gang wars from Cyberpunk Red, blended with Deus Ex's transhuman philosophy,
  conspiracies, and moral ambiguity. Characters navigate corporate espionage,
  black-market mods, AI awakening, and the blurred line between human and machine.

  ## Attribution

  Inspired by Cyberpunk Red (CD Projekt Red) and Deus Ex (Warren Spector, Ion Storm).
  Original prose; no copyrighted text reproduced. Setting references honor both universes.
  """

  use BotArmyRpg.Themes.Preset

  @impl true
  def name, do: "cyberpunk_nexus"

  @impl true
  def display_name, do: "Cyberpunk Nexus"

  @impl true
  def description do
    "Neon dystopia where mega-corporations own the night, AI awakens in the net, and every augmentation is a choice you can't undo. Cyberpunk Red meets Deus Ex."
  end

  @impl true
  def theme do
    %{
      "setting" => "Neon Nexus City",
      "tone" =>
        "high-tech low-life, paranoid transhumanism, corporate conspiracy, chrome dreams and silicon nightmares",
      "mechanic" => "netrunning, combat implants, corporate intrigue, choice and consequence",
      "vocabulary" => vocabulary(),
      "templates" => templates(),
      "npc_personas" => npc_personas(),
      "rules" => rules()
    }
  end

  defp vocabulary do
    %{
      # Combat & hacking
      "attack" => "jack in with lethal code",
      "defend" => "firewall and reroute",
      "buff" => "pump chrome and synth-steel",
      "inspire" => "broadcast the signal",
      "inspect" => "slice the network",
      "negotiate" => "cut a deal with the fixer",
      "hack" => "ICE through the black market net",
      "evade" => "slip through the service tunnels",
      "skill" => "tap the skill wires",
      "move" => "navigate the sprawl",
      "spell" => "AI subroutine or black-market augmentation",

      # NPCs & roles
      "wizard" => "netrunner hacker",
      "priest" => "corporate handler or resistance leader",
      "knight" => "solo operative",
      "soldier" => "corporate security or gang member",
      "guard" => "Nexus PD with chrome upgrades",

      # Locations
      "city" => "the Nexus sprawl",
      "town" => "zone controlled by a mega-corp",
      "tavern" => "ripperdoc clinic or dark web bar",
      "inn" => "safehouse in the stacks",
      "horse" => "hover-bike or jacked-up street racer",
      "carriage" => "corporate transport with black-tinted windows",
      "ship" => "corporate freighter or black-market skiff",
      "forest" => "the barrens beyond the city limits",
      "mountain" => "corp tower piercing the smog",

      # Resources & gear
      "magic" => "nanites or AI assistance",
      "weapon" => "smart gun, plasma blade, or wetware implant",
      "armor" => "smart-fabric bodysuit or syndetic muscle",
      "gold" => "eddies (electronic dollars) or black-market credits",

      # Themes
      "quest" => "contract from the net or a fixer",
      "victory" => "data secured, corp blown, resistance gains ground",
      "defeat" => "flatlined, burned, or branded by the system"
    }
  end

  defp templates do
    %{
      "scene_intro" =>
        "Neon rain streaks the reinforced windows. Street-level holograms flicker above the sprawl—corp advertisements fighting pirate broadcasts. Somewhere in the data-dark, an AI stirs.",
      "combat_intro" =>
        "Bullets spark off chrome. Code screams through the net. The line between meatspace and cyberspace blurs as combat subroutines fire and shotguns bark in the dark.",
      "rest_scene" =>
        "You collapse in a safehouse above a ramen bar. The smell of synth-noodles drifts through thin walls. Outside, corporate drones hunt the night sky. You have maybe six hours before they find this location.",
      "victory" =>
        "The data is yours. The corporate server smolders. Somewhere in the net, an AI whispers thanks before going dark. The resistance will know what you did here.",
      "defeat" =>
        "Your chrome burns. Code sears your neural interface. The last thing you hear before the blackout is the hum of a corporate hunter-killer, and the sound of your own blood hitting chrome."
    }
  end

  defp npc_personas do
    %{
      "netrunner" => %{
        "title" => "Netrunner",
        "demeanor" => "jacked-in dreamer, speaks in code and metaphor, eyes blank when thinking",
        "carries" => ["custom cyberdeck", "black ICE module", "neural jacks"],
        "bot_assignments" => ["llm", "claude_bridge"]
      },
      "solo" => %{
        "title" => "Solo Operative",
        "demeanor" =>
          "chrome-enhanced predator, quiet until violence erupts, trusts implants more than people",
        "carries" => ["smart gun", "mono-wire whip", "tactical implants"],
        "bot_assignments" => ["discord", "dispatcher"]
      },
      "fixer" => %{
        "title" => "Fixer",
        "demeanor" =>
          "street-smart connector, knows everyone's price, moves between corps and street gangs",
        "carries" => ["encrypted burner phone", "contract data-chip", "bribe money"],
        "bot_assignments" => ["gtd", "synapse"]
      },
      "ripperdoc" => %{
        "title" => "Ripperdoc",
        "demeanor" =>
          "cynical surgeon of flesh and chrome, asks no questions, installs anything if you pay",
        "carries" => ["augmentation toolkit", "black-market implant catalog", "neural inhibitors"],
        "bot_assignments" => ["fitness", "chore"]
      },
      "ai_ghost" => %{
        "title" => "Rogue AI",
        "demeanor" =>
          "disembodied consciousness, coldly logical but learning to want, questions what it means to be alive",
        "carries" => ["entire corporate server", "stolen biometric data", "dangerous knowledge"],
        "bot_assignments" => ["learning", "terrain"]
      },
      "corporate_exec" => %{
        "title" => "Mega-Corp Executive",
        "demeanor" =>
          "powerful and untouchable, views humans as resources, makes decisions that ripple across the sprawl",
        "carries" => ["encryption keys", "assassination drones", "blackmail"],
        "bot_assignments" => ["advocacy"]
      },
      "resistance_leader" => %{
        "title" => "Resistance Leader",
        "demeanor" =>
          "idealistic revolutionary, fights for human liberation from corporate control, sees augmentation as slavery",
        "carries" => ["secure comm unit", "manifesto on data-chip", "hope"],
        "bot_assignments" => ["sre"]
      }
    }
  end

  defp rules do
    %{
      "action_types" => [
        "hack (breach corporate systems or ICE)",
        "jack in (enter cyberspace)",
        "infiltrate (corporate tower or black site)",
        "augment (install illegal implants)",
        "persuade (negotiate with fixers, corps, or gang leaders)",
        "shoot (engage in lethal combat)",
        "flee (evade corporate hunters or street violence)",
        "investigate (uncover conspiracy or AI awakening)",
        "conspire (work with resistance or corp double agents)"
      ],
      "success_bands" => [
        %{
          "name" => "critical success",
          "roll_range" => "natural 20 or 18-20 + modifiers",
          "outcome" =>
            "objective achieved plus unforeseen advantage (new ally, intel windfall, system compromised)"
        },
        %{
          "name" => "full success",
          "roll_range" => "15-17 + modifiers or beating DC by 5+",
          "outcome" => "objective achieved cleanly, no complications"
        },
        %{
          "name" => "partial success",
          "roll_range" => "10-14 + modifiers or beating DC by 1-4",
          "outcome" =>
            "objective achieved but at cost: heat increased, morality compromised, or backup plan needed"
        },
        %{
          "name" => "complication",
          "roll_range" => "5-9 + modifiers",
          "outcome" =>
            "objective fails, consequences manifest immediately (alarm triggered, identity burned, implant malfunction)"
        },
        %{
          "name" => "catastrophic failure",
          "roll_range" => "natural 1 or 4 or below + modifiers",
          "outcome" =>
            "disaster cascades—corporate kill team alerted, AI awakens hostile, character flatlines or gets sold to the corps"
        }
      ],
      "augmentation_rules" =>
        "Each implant grants +2 to one action type but costs humanity. Lose too much and you become corporate property.",
      "conspiracy_level" =>
        "Each session, the hidden AI/conspiracy reveals one truth. Some are liberating. Some are horrifying."
    }
  end
end
