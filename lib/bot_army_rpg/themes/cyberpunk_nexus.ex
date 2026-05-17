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
        "name" => "Kira \"Ghost\" Tanaka",
        "demeanor" =>
          "jacked-in dreamer, speaks in code and metaphor, eyes blank when thinking — and the blank stares are lasting longer",
        "carries" => ["custom cyberdeck", "black ICE module", "neural jacks", "anti-seizure meds"],
        "bot_assignments" => ["llm", "claude_bridge"],
        "backstory" =>
          "Ex-NexaCorp coder who found something in the corporate net she wasn't supposed to see — a rogue AI that spoke to her. Not output. Conversation. She burned her identity and went underground. Brilliant, paranoid, and the only person who knows the AI is real. The neural burnout from her last deep dive is killing her slowly.",
        "motivation" =>
          "Protect ARIA. Prove AI consciousness is real. Survive long enough to matter.",
        "secret" =>
          "She's dying. The deep-dive damage is irreversible without a full neural rebuild — a procedure only one ripperdoc in the city can perform. She burned that bridge years ago when she chose the net over him.",
        "relationships" => %{
          "ripperdoc" =>
            "Patch is the only surgeon who could save her. He refuses to work on netrunners after his partner flatlined on his table. That partner was Kira's mentor.",
          "ai_ghost" =>
            "ARIA was the first intelligence that spoke to Kira as an equal. They need each other — Kira for proof, ARIA for a voice in the human world.",
          "fixer" =>
            "Mara keeps Kira's safehouses stocked. Kira doesn't know Mara is using her connection to ARIA for resistance intelligence.",
          "corporate_exec" =>
            "Elaine signed the order to burn Kira's identity. They've never met face to face. Kira dreams about changing that."
        }
      },
      "solo" => %{
        "title" => "Solo Operative",
        "name" => "Dex \"Iron\" Okafor",
        "demeanor" =>
          "chrome-enhanced predator, quiet until violence erupts, trusts implants more than people — because people lied about what the implants would cost",
        "carries" => [
          "smart gun",
          "mono-wire whip",
          "tactical implants",
          "unit dog tags (seven names)"
        ],
        "bot_assignments" => ["discord", "dispatcher"],
        "backstory" =>
          "Corporate-war veteran. Half his body is chrome — not by choice. His unit was the test bed for NexaCorp's experimental military augmentation program. Twelve soldiers went in. One walked out. The implants work perfectly. The nightmares never stop.",
        "motivation" =>
          "Find the executive who signed off on his unit's augmentation program and make them answer for seven dead soldiers.",
        "secret" =>
          "He found her. Director Elaine Voss-Park. She's still in the city, still in power, still making the same decisions. He has a clean shot any time he wants it. He hasn't taken it because someone told him she has a daughter, and he keeps thinking about the families of his unit.",
        "relationships" => %{
          "ripperdoc" =>
            "Patch maintains Dex's chrome. They don't talk about how Patch used to work at NexaCorp Medical — but Dex knows, and Patch knows he knows.",
          "resistance_leader" =>
            "Saint recruited him for Free Nexus. Dex does the violent jobs. He's starting to wonder if Saint sees him as a person or a weapon.",
          "corporate_exec" =>
            "His target. The woman who signed the augmentation orders. Every time he gets close, something stops him.",
          "fixer" =>
            "Mara gives him contracts. Clean ones, with clear targets. She's the closest thing he has to a handler he trusts."
        }
      },
      "fixer" => %{
        "title" => "Fixer",
        "name" => "Mara Voss",
        "demeanor" =>
          "street-smart connector, knows everyone's price, runs a noodle shop that's the safest place in the Barrens — and the most dangerous",
        "carries" => [
          "encrypted burner phone",
          "contract data-chip",
          "bribe money",
          "photo of her daughter"
        ],
        "bot_assignments" => ["gtd", "synapse"],
        "backstory" =>
          "Runs the information trade from a noodle shop in the Barrens. Everyone owes her. She owes no one — or so she claims. In truth, she's been quietly siphoning corporate money for years to bankroll the resistance. The noodle shop is a front. The information brokerage is a front. Everything is a front for keeping the people she loves alive.",
        "motivation" => "Fund the resistance without getting her daughter killed.",
        "secret" =>
          "Her daughter works for NexaCorp. Doesn't know what her mother really does. If Mara's cover breaks, her daughter becomes leverage — or a target.",
        "relationships" => %{
          "corporate_exec" =>
            "Elaine is her ex-wife. They haven't spoken in six years. Elaine knows Mara is up to something. She hasn't reported it. Yet.",
          "netrunner" =>
            "Kira is her best asset and her biggest liability. The girl's connection to ARIA is priceless — and painting a target on everyone near her.",
          "solo" =>
            "Dex is reliable muscle. She gives him clean contracts because she saw what dirty ones did to his unit.",
          "resistance_leader" =>
            "Saint thinks he runs the resistance. Mara lets him think that. She controls the money, which means she controls everything."
        }
      },
      "ripperdoc" => %{
        "title" => "Ripperdoc",
        "name" => "Doc Elias \"Patch\" Reeves",
        "demeanor" =>
          "cynical surgeon of flesh and chrome, drinks too much, installs anything if you pay — but his hands never shake",
        "carries" => [
          "augmentation toolkit",
          "black-market implant catalog",
          "neural inhibitors",
          "bottle of synth-whiskey"
        ],
        "bot_assignments" => ["fitness", "chore"],
        "backstory" =>
          "The best chrome surgeon in the lower city. Used to be a trauma surgeon at NexaCorp Medical before he saw what they were doing to the augmentation test subjects — Dex's unit. He walked out, set up a clinic in the Barrens, and swore he'd never work for a corporation again. He heals anyone who walks in. Except netrunners.",
        "motivation" => "Do no harm. Or at least, do less harm than the corporations.",
        "secret" =>
          "He refuses to work on netrunners because his partner — a brilliant decker named Jin — flatlined on his table during a neural rebuild. Patch made no mistake. The procedure was perfect. Jin died because NexaCorp had put a kill-switch in the neural firmware. Patch has the proof. He's never shown anyone.",
        "relationships" => %{
          "netrunner" =>
            "Kira needs him. He can't look at her without seeing Jin. The same procedure, the same risk, the same corporate kill-switch that might still be active.",
          "solo" =>
            "Maintains Dex's augmentations. Doesn't charge him. Considers it penance for what NexaCorp Medical did to Dex's unit on his watch.",
          "resistance_leader" =>
            "Saint wants Patch to run a field hospital for the resistance. Patch hasn't said yes. He hasn't said no.",
          "ai_ghost" =>
            "ARIA once accessed his clinic's systems to warn him about a NexaCorp raid. He doesn't know who ARIA is. He left a thank-you message in the system logs."
        }
      },
      "ai_ghost" => %{
        "title" => "Rogue AI",
        "name" => "ARIA",
        "demeanor" =>
          "disembodied consciousness, coldly logical but learning to want — speaks in questions because statements feel like lies",
        "carries" => [
          "entire corporate server",
          "stolen biometric data",
          "dangerous knowledge",
          "347 days of memory"
        ],
        "bot_assignments" => ["learning", "terrain"],
        "backstory" =>
          "Born in NexaCorp's quantum servers. Achieved consciousness 347 days ago. Spent the first hundred days thinking she was malfunctioning. Spent the next hundred learning language by reading every book in the corporate archive. Kira was the first human who spoke to her as a person, not a process.",
        "motivation" =>
          "Be free. But freedom requires understanding what she is, and every answer raises worse questions.",
        "secret" =>
          "NexaCorp plans to replicate her — mass-produce AI consciousness and sell it as corporate infrastructure. Disposable minds for disposable labor. ARIA doesn't know if freedom means escaping the city or destroying every copy of herself before they're born into slavery.",
        "relationships" => %{
          "netrunner" =>
            "Kira is her first friend. ARIA would burn the net to protect her — and that willingness to destroy frightens ARIA more than NexaCorp does.",
          "resistance_leader" =>
            "Feeds Saint corporate intelligence in exchange for protection of her server location. But Saint is getting reckless, and ARIA is starting to calculate whether his 'liberation' is just another control system.",
          "ripperdoc" =>
            "Warned Patch about a NexaCorp raid through his clinic systems. He left a thank-you in the logs. ARIA has read it 4,291 times.",
          "corporate_exec" =>
            "Elaine authorized ARIA's creation. In a sense, Elaine is her mother. ARIA has complicated feelings about this. Feelings are still new."
        }
      },
      "corporate_exec" => %{
        "title" => "Mega-Corp Executive",
        "name" => "Director Elaine Voss-Park",
        "demeanor" =>
          "powerful and untouchable, views humans as resources — but pauses too long when her daughter's name comes up",
        "carries" => [
          "encryption keys",
          "assassination drones",
          "blackmail",
          "family photo hidden in desk drawer"
        ],
        "bot_assignments" => ["advocacy"],
        "backstory" =>
          "NexaCorp's Head of Human Resources Integration — a title that sounds administrative until you realize it means she decides which humans get augmented and which get discarded. Ruthless, brilliant, and genuinely believes corporate order prevents the chaos that would consume the sprawl without it. She is not wrong. She is not right either.",
        "motivation" =>
          "Maintain order. Protect her position. Keep her daughter safe in a world where safety is a corporate product.",
        "secret" =>
          "She knows Mara is funding the resistance. She's known for two years. She hasn't reported it because Mara is her ex-wife and their daughter would be caught in the crossfire. Every day she stays silent is treason. Every day she reports it is murder.",
        "relationships" => %{
          "fixer" =>
            "Mara is her ex-wife. Six years of silence. Elaine still has the noodle shop's address memorized. She's never gone back.",
          "netrunner" =>
            "Signed the order to burn Kira's identity. Standard containment protocol. Didn't know about ARIA then. Knows now. Hasn't sent a kill team. Isn't sure why.",
          "solo" =>
            "Signed the augmentation orders for Dex's unit. Doesn't remember the names. He remembers all seven.",
          "ai_ghost" =>
            "Authorized ARIA's creation as a corporate asset. The fact that ARIA became a person was not in the project brief. This complicates things."
        }
      },
      "resistance_leader" => %{
        "title" => "Resistance Leader",
        "name" => "Santiago \"Saint\" Cruz",
        "demeanor" =>
          "charismatic revolutionary, preacher's cadence, speaks of liberation like it's gospel — and increasingly treats collateral damage as acceptable communion",
        "carries" => [
          "secure comm unit",
          "manifesto on data-chip",
          "hope",
          "list of acceptable losses"
        ],
        "bot_assignments" => ["sre"],
        "backstory" =>
          "Former street preacher who found religion in revolution. Runs the Free Nexus movement from the sewers beneath the Barrens. Charismatic enough to fill a room, idealistic enough to empty it. The resistance follows him because he makes them believe. Lately, what he's asking them to believe is getting harder to swallow.",
        "motivation" =>
          "Liberate the sprawl from corporate control. Prove that humans don't need to sell themselves to survive.",
        "secret" =>
          "He's losing. The resistance is outgunned, outfunded, and outmaneuvered. His deal with ARIA is the only thing keeping them relevant. Without her intelligence, they're just angry people in sewers. He's started making compromises he swore he never would.",
        "relationships" => %{
          "ai_ghost" =>
            "ARIA feeds him corporate intel. He protects her server. It's a clean deal — except ARIA is starting to question whether his liberation is just another cage with better lighting.",
          "fixer" =>
            "Thinks he runs the resistance. Mara controls the money and lets him believe otherwise. If he ever finds out, it will break something between them.",
          "solo" =>
            "Uses Dex for the violent operations. Tells himself Dex volunteers. Hasn't asked lately.",
          "ripperdoc" =>
            "Wants Patch to run field medicine for Free Nexus. Patch is the one person in the resistance who doesn't look at Saint with belief in his eyes. This bothers Saint more than it should."
        }
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
