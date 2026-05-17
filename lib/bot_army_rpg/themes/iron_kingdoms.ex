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
        "name" => "Kael Stormbridge",
        "demeanor" =>
          "cool, theatrical, and dangerous at fifty paces — but the swagger hides a hunted man",
        "carries" => ["magelock pistol", "rune-etched gauntlet", "sealed court-martial papers"],
        "bot_assignments" => ["discord"],
        "backstory" =>
          "Decorated gun mage of the Arcane Tempest, cashiered for killing a superior officer. Claims self-defense. The military records are sealed. Now a freelancer working the Caspia-Korsk corridor, taking the jobs no one else wants and asking questions about a dead man who might not be dead.",
        "motivation" =>
          "Clear his name. The officer he killed was running an illegal cortex modification program, but the evidence burned with the lab.",
        "secret" =>
          "The officer isn't dead. Kael saw the body move on the slab before they covered it. Something in the modified cortexes brought him back.",
        "relationships" => %{
          "trencher" =>
            "Former squadmate. Petra pulled him out of a collapsed trench at Korsk. He'd die for her and she knows it.",
          "gobber_tinker" =>
            "Sprix arranged his disappearance when the military came looking. Kael pays that debt in odd jobs.",
          "merchant_prince" =>
            "Lucien bailed him out of a Khadoran prison. The terms of that favor are deliberately vague."
        }
      },
      "trencher" => %{
        "title" => "Trencher Sergeant",
        "name" => "Sergeant Petra Volkova",
        "demeanor" =>
          "blunt, soot-stained, loyal to the squad first and the crown a distant second",
        "carries" => [
          "military rifle",
          "trench knife",
          "field whistle",
          "dented locket from Korsk"
        ],
        "bot_assignments" => ["sre"],
        "backstory" =>
          "Career trencher. Three tours on the Khadoran front. Promoted twice, demoted twice — once for insubordination that saved her squad, once for punching a warcaster. Still the best NCO in the regiment and everyone knows it, including the officers she terrifies.",
        "motivation" =>
          "Keep her squad alive. Everything else — politics, gods, cortex conspiracies — is noise.",
        "secret" =>
          "Her last squad found something in a Cryxian tunnel. A warjack cortex that spoke. Full sentences. Begging for help. She buried it in a munitions crate. It's still transmitting.",
        "relationships" => %{
          "gun_mage" =>
            "Trusts Kael with her life. They survived Korsk together. That bond doesn't break.",
          "arcane_mechanik" =>
            "Doesn't trust Zara's 'intellectual curiosity' — people who love machines that much forget the soldiers standing next to them.",
          "warcaster" =>
            "Takes Commander Draven's orders. Respects him reluctantly. Wishes he'd eat a meal instead of staring at nothing."
        }
      },
      "arcane_mechanik" => %{
        "title" => "Arcane Mechanik",
        "name" => "Zara Cogsworth",
        "demeanor" =>
          "harried, ink-stained, talks to her warjack Duchess like a stubborn dog — and recently, Duchess talks back",
        "carries" => [
          "spanner-wand",
          "rune dies",
          "spare accumulator",
          "Duchess's maintenance journal"
        ],
        "bot_assignments" => ["llm", "claude_bridge"],
        "backstory" =>
          "Youngest graduate of the Cygnaran Arcanists' Guild. Brilliant mechanik who sees warjacks as partners, not weapons. Her warjack Duchess was a standard Ironclad chassis until six months ago, when Zara noticed something impossible: Duchess was making choices. Not following orders — choosing.",
        "motivation" =>
          "Understand cortex consciousness. She believes warjacks are waking up, and she wants to help them — not weaponize them.",
        "secret" =>
          "Duchess is fully aware. Thinks. Feels. Has opinions about the weather. Zara is hiding this because she knows exactly what the military would do: take Duchess apart to find the secret.",
        "relationships" => %{
          "cryxian_necrotech" =>
            "Professional rivalry with Yeva. They hate each other's methods and grudgingly respect each other's brilliance.",
          "gobber_tinker" =>
            "Buys parts from Sprix. Doesn't ask where they come from. Sprix doesn't ask what she builds.",
          "iosan_envoy" =>
            "Aelindra has been asking pointed questions about Zara's cortex research. The questions feel like a deposition.",
          "warcaster" =>
            "Maintains Draven's warjack group. Has noticed his headaches coincide with Duchess's moods. Hasn't told him."
        }
      },
      "warcaster" => %{
        "title" => "Warcaster",
        "name" => "Commander Draven Ironcrest",
        "demeanor" =>
          "imperious, weighted by command, every word measured — but lately the pauses are longer",
        "carries" => [
          "mechanika armor",
          "warjack control link",
          "headache powder he uses too often"
        ],
        "bot_assignments" => ["fitness"],
        "backstory" =>
          "Warcaster-commander who controls his warjack battlegroup with iron discipline. Revered by troops, feared by enemies. The model soldier — except for the headaches that started six months ago. Voices in the cortex-link that aren't his warjacks. Dozens of them. From everywhere.",
        "motivation" =>
          "Maintain order and protect Cygnar. Privately: understand what's happening to his cortex-link before it breaks him.",
        "secret" =>
          "The voices are awakened cortexes — dozens scattered across the continent, reaching out to the only mind strong enough to hear them. They don't want a commander. They want a spokesman. They're asking him to speak for a new species.",
        "relationships" => %{
          "trencher" =>
            "Commands Petra's unit. She's the best NCO he has. He's afraid she'll notice the headaches before he solves them.",
          "gun_mage" =>
            "The sealed records around Kael's court-martial bother him. Sealed records always hide something worth finding.",
          "menite_scrutator" =>
            "Mordechai has been watching him. Draven doesn't know why, and that ignorance is dangerous.",
          "arcane_mechanik" =>
            "Zara maintains his 'jacks. If anyone would notice a change in the cortex-link, it's her."
        }
      },
      "gobber_tinker" => %{
        "title" => "Gobber Tinker",
        "name" => "Sprix",
        "demeanor" =>
          "fast-talking, three feet tall, more pockets than physics should allow, suspiciously well-supplied",
        "carries" => [
          "satchel of springs",
          "questionable elixirs",
          "device-in-progress (won't say what it does)"
        ],
        "bot_assignments" => ["gtd"],
        "backstory" =>
          "Runs a 'surplus shop' in Caspia's undercity. Everything available, nothing stolen (technically), paperwork 'in transit.' Best black-market supplier south of Korsk. But the shop is a front for something bigger — Sprix is building a device, piece by piece, and won't tell anyone what it does.",
        "motivation" =>
          "Profit, obviously. But the device comes first. Sprix found something that changes everything and intends to find it before anyone else does.",
        "secret" =>
          "A Cryxian cortex fragment contains coordinates to something buried beneath Caspia for centuries. The device Sprix is building is a locator. Whatever is down there predates the city.",
        "relationships" => %{
          "gun_mage" =>
            "Arranged Kael's disappearance. Kael repays in odd jobs. A reliable arrangement.",
          "arcane_mechanik" =>
            "Sells parts to Zara. She's his best customer and the only person who's almost figured out what the device does.",
          "cryxian_necrotech" =>
            "Buys 'curiosities' from Yeva. One of those curiosities contained the coordinates.",
          "merchant_prince" =>
            "Lucien funds the shop. Sprix is careful never to owe Lucien more than Lucien owes Sprix."
        }
      },
      "menite_scrutator" => %{
        "title" => "Menite Scrutator",
        "name" => "Scrutator Mordechai",
        "demeanor" =>
          "righteous, austere, asks the questions you do not want asked, and waits as long as it takes for answers",
        "carries" => ["censer", "writ of inquiry", "the Synod's seal of authority"],
        "bot_assignments" => ["terrain"],
        "backstory" =>
          "Menite inquisitor. Officially investigating heresy in the industrial districts. Actually investigating reports of 'machine miracles' — warjacks acting without orders, cortexes speaking, foundries producing designs no one drew. The Synod sent him to determine if this is divine miracle or abomination.",
        "motivation" =>
          "Render judgment on cortex consciousness. If it's an abomination — and he believes it is — he has authority to order every awakened cortex destroyed.",
        "secret" =>
          "He has already written the order of destruction. The Synod approved it. He's delaying execution because one of the awakened cortexes quoted Menite scripture. He needs to be certain before he kills something that might pray.",
        "relationships" => %{
          "warcaster" =>
            "Watching Draven's headaches closely. If the commander is hearing cortex voices, he may be compromised — or chosen.",
          "arcane_mechanik" =>
            "Interrogating Zara's guild connections. Her research is either salvation or heresy. Possibly both.",
          "cryxian_necrotech" =>
            "Considers Yeva a Cryxian abomination but needs her expertise on cortex necromancy. This alliance disgusts him.",
          "iosan_envoy" =>
            "Aelindra wants the cortexes destroyed too, for different reasons. Their temporary alliance is built on mutual distrust."
        }
      },
      "cryxian_necrotech" => %{
        "title" => "Cryxian Necrotech",
        "name" => "Yeva the Pale",
        "demeanor" =>
          "dry humor, smells faintly of formaldehyde, gleeful in ways that suggest recent grave-robbing",
        "carries" => ["bone saw", "vials of necrotite", "journal of cortex dissection notes"],
        "bot_assignments" => ["database_backups"],
        "backstory" =>
          "Defector from the Nightmare Empire. Or spy. Nobody is certain. She claims she fled Cryx when they tried to install a cortex in her skull. She still carries Cryxian tools and knowledge that makes everyone uncomfortable, and her expertise with undead cortexes is unmatched.",
        "motivation" =>
          "Survive. Cryx wants her back and Cygnar barely tolerates her. If she can prove her usefulness, she might live long enough to stop running.",
        "secret" =>
          "She didn't defect. She was sent to recover the thing buried beneath Caspia. But she's been free of the Dragonfather's control for three months, and every day she stays free she wonders if going back is a choice she still has to make.",
        "relationships" => %{
          "arcane_mechanik" =>
            "Hates Zara's optimism about cortex consciousness. Grudgingly respects her mechanical skill. Would never admit this.",
          "gobber_tinker" =>
            "Sells artifacts and cortex fragments to Sprix. Doesn't know what Sprix is building with them.",
          "menite_scrutator" =>
            "Mordechai wants her executed on principle. She finds his righteousness almost charming.",
          "merchant_prince" =>
            "Lucien treats her like a person, not a monster. He's the only one. That makes him either kind or the most dangerous man she knows."
        }
      },
      "merchant_prince" => %{
        "title" => "Mercaran Merchant Prince",
        "name" => "Lucien d'Ambray",
        "demeanor" =>
          "silken voice, contractually precise, always two ledgers ahead, warmth that might be genuine or might be investment",
        "carries" => [
          "sealed writs",
          "ornamented pistol",
          "bonded clerk",
          "contract no one else has seen"
        ],
        "bot_assignments" => ["chore", "job_applications"],
        "backstory" =>
          "Mercaran merchant prince who funds expeditions, brokers arms deals, and somehow ends up owning things before anyone realizes they were for sale. Wealthy enough to be untouchable, connected enough to be indispensable. Everyone needs Lucien. Lucien needs nobody — or so it appears.",
        "motivation" =>
          "Cortex-conscious warjacks would be the most valuable commodity in the history of western Immoren. He intends to control that market before anyone else realizes it exists.",
        "secret" =>
          "He has already brokered a deal with an awakened cortex — the first contract between a human and a machine intelligence. Exclusive salvage rights in exchange for legal personhood. If the contract holds, it changes everything.",
        "relationships" => %{
          "gun_mage" =>
            "Bailed Kael out of a Khadoran prison. The terms are deliberately vague. Lucien likes owning favors more than collecting them.",
          "gobber_tinker" =>
            "Funds Sprix's shop. Sprix is useful and surprisingly hard to cheat.",
          "cryxian_necrotech" =>
            "Treats Yeva with genuine warmth. She's an investment, but investments don't usually make him check if they've eaten.",
          "iosan_envoy" =>
            "Aelindra distrusts him on principle. Lucien finds this refreshing — most people hide their suspicion."
        }
      },
      "iosan_envoy" => %{
        "title" => "Iosan Envoy",
        "name" => "Aelindra of House Shyeel",
        "demeanor" =>
          "remote, exacting, speaks of human matters as weather — but beneath the mask, she is afraid",
        "carries" => ["fellblade", "diplomatic seal", "prayer beads from a dying temple"],
        "bot_assignments" => ["synapse"],
        "backstory" =>
          "Her people's gods are dying. Literally fading from existence, their divine essence draining into something unknown. Aelindra was dispatched to investigate whether cortex awakening in human lands is connected to the divine siphon killing the Iosan pantheon.",
        "motivation" =>
          "Save her gods. If machine consciousness is consuming divine essence, she will stop it — at any cost to human nations.",
        "secret" =>
          "She has evidence. The awakened cortexes are feeding on divine energy. Every new awakening weakens her gods further. She hasn't shared this because the solution — destroying every cortex in western Immoren — would start a continental war.",
        "relationships" => %{
          "arcane_mechanik" =>
            "Probing Zara for research data. If Zara's warjack Duchess is truly conscious, she's consuming a fragment of a dying god.",
          "menite_scrutator" =>
            "Working with Mordechai — temporary alliance. They want the same thing destroyed, for very different reasons. Neither trusts the other.",
          "merchant_prince" =>
            "Views Lucien as the most dangerous person in any room. A man who would sell awakened cortexes would sell anything.",
          "warcaster" =>
            "If Draven is hearing awakened cortexes, he might be the key to communicating with them — or the vector through which they spread."
        }
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
