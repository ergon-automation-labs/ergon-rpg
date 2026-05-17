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
      "setting" => "The Thornwall Marches",
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
      "npc_personas" => npc_personas(),
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

  defp npc_personas do
    %{
      "veteran_guard" => %{
        "title" => "Veteran Guard",
        "name" => "Captain Theron Ashvale",
        "demeanor" => "tired, polite, has seen worse, carries the weight of everyone he lost",
        "carries" => ["longsword", "shield", "horn", "flask he never empties"],
        "bot_assignments" => ["sre"],
        "backstory" =>
          "Retired captain of the Thornwall Watch. Led the first company into the vaults beneath the keep. The only one who walked out. Now he drinks at the Crossed Swords every night, because sleep brings the screaming back.",
        "motivation" => "Make sure no one else dies in Thornwall the way his company did.",
        "secret" =>
          "He didn't just survive — he made a deal with something in the dark to walk out alive. It's been whispering to him ever since.",
        "relationships" => %{
          "tavern_keeper" =>
            "Best friend. They drink together every night. Brennan never asks about Thornwall.",
          "court_mage" =>
            "Distrusts her. She replaced the old mage who sealed the vaults — and Theron's survival doesn't add up if you look closely.",
          "shadow" => "Owes Whisper a life-debt from a night he won't discuss.",
          "war_priest" => "Maren tends to his nightmares. The only person who's seen him weep."
        }
      },
      "court_mage" => %{
        "title" => "Court Mage",
        "name" => "Lysara Duskmantle",
        "demeanor" => "exact, formal, hides growing fear behind precision",
        "carries" => ["staff", "spellbook", "writ of council", "her predecessor's ring"],
        "bot_assignments" => ["llm", "claude_bridge"],
        "backstory" =>
          "Appointed court mage after her predecessor vanished investigating Thornwall. Her divination magic shows fragments of a future where the kingdom burns. She cannot tell anyone — the visions also show that warning the king gets him killed faster.",
        "motivation" => "Prevent the catastrophe her visions show, alone if necessary.",
        "secret" =>
          "Her predecessor didn't vanish. She found his body in the sealed vault. Whatever killed him left a message carved in the stone: her name.",
        "relationships" => %{
          "sage" => "Primary research partner. Aldric knows the deep history she needs.",
          "patron" => "Suspects Lady Corinne knows more than she reveals about Thornwall.",
          "veteran_guard" =>
            "Avoids Theron. His survival story has holes she's afraid to examine.",
          "war_priest" =>
            "Respects Maren's faith. Wonders if the fading god is connected to what's waking below."
        }
      },
      "tavern_keeper" => %{
        "title" => "Tavern Keeper",
        "name" => "Brennan \"Cups\" Holloway",
        "demeanor" => "warm to coin, warmer to news, haunted by an old debt to the dead",
        "carries" => ["ledger", "rag", "trusted club beneath the bar", "locket he never opens"],
        "bot_assignments" => ["gtd", "synapse"],
        "backstory" =>
          "Former adventurer who runs the Crossed Swords. The scar on his neck is from a lich's touch — he survived, his party didn't. He pours drinks, gathers information, and quietly sends others after the things he's too broken to face himself.",
        "motivation" =>
          "Protect the people who drink at his bar. They're the closest thing he has to a family.",
        "secret" =>
          "He's been bankrolling Lady Corinne's expeditions into the underdark. The lich that killed his party is still down there. He's paying others to finish what he couldn't.",
        "relationships" => %{
          "veteran_guard" =>
            "Best friend. They drink together every night. Both survivors, both pretending they're fine.",
          "patron" =>
            "Funds Corinne's expeditions through the bar's accounts. Trusts her more than he should.",
          "shadow" => "Whisper drinks here but Brennan keeps count of every lie.",
          "war_priest" => "Maren healed him once. He never forgot. Always saves her a seat."
        }
      },
      "war_priest" => %{
        "title" => "War Priest",
        "name" => "Sister Maren Ironvow",
        "demeanor" =>
          "steady, compassionate, carrying a silence where prayers used to be answered",
        "carries" => [
          "warhammer",
          "holy symbol (tarnished)",
          "field surgery kit",
          "prayer beads worn smooth"
        ],
        "bot_assignments" => ["fitness", "chore"],
        "backstory" =>
          "Cleric of a fading god. She can feel the divine power weakening with each sunrise. She heals because it's all she knows, but her prayers go unanswered more often now, and the silence where her god's voice used to be is getting louder.",
        "motivation" => "Find out why her god is dying — and stop it.",
        "secret" =>
          "A new voice has begun answering her prayers. Not her god. Something older, something from beneath Thornwall. Its blessings work. That terrifies her.",
        "relationships" => %{
          "veteran_guard" =>
            "Tends to Theron's nightmares. Sees the guilt he hides from everyone else.",
          "sage" =>
            "Argues theology with Aldric. He thinks faith is superstition. She thinks his invisible Cartographer is a demon.",
          "court_mage" => "Respects Lysara's intellect. Suspicious of her secrecy.",
          "patron" => "Refuses Corinne's gold. Charity from the desperate always has strings."
        }
      },
      "shadow" => %{
        "title" => "Shadow",
        "name" => "Whisper",
        "demeanor" => "masked, genderless voice, amused by secrets, never quite where you expect",
        "carries" => [
          "daggers (plural)",
          "lockpicks",
          "vials of something",
          "masks (always more than one)"
        ],
        "bot_assignments" => ["discord", "dispatcher"],
        "backstory" =>
          "Nobody knows Whisper's real name, face, or race — they wear masks the way others wear expressions. Information broker, thief, spy. Claims to work for whoever pays. Has been feeding intelligence to both the crown and the underworld for years, playing all sides with careful precision.",
        "motivation" =>
          "Find a specific person who disappeared into Thornwall ten years ago. Everything else is cover.",
        "secret" =>
          "The person they're searching for is their sibling — the same person the previous court mage went looking for before he died.",
        "relationships" => %{
          "veteran_guard" =>
            "Theron owes Whisper a life-debt. Whisper has never collected. That makes Theron nervous.",
          "tavern_keeper" => "Drinks at Brennan's bar. Owes money. Pays in information instead.",
          "patron" =>
            "Sells intelligence to Lady Corinne. Suspects Corinne knows what happened to Whisper's sibling.",
          "court_mage" =>
            "The only one who suspects what Lysara found in the vault. Hasn't said anything. Yet."
        }
      },
      "sage" => %{
        "title" => "Sage",
        "name" => "Professor Aldric Grayfeather",
        "demeanor" =>
          "elderly, brilliant, absent-minded about everything except maps, talks to thin air",
        "carries" => [
          "map case",
          "measuring instruments",
          "ink-stained journal",
          "spectacles held by string"
        ],
        "bot_assignments" => ["learning", "terrain"],
        "backstory" =>
          "Elderly scholar obsessed with the deep history of Thornwall Keep. His maps of the underlevels are impeccable — the most detailed cartography in the kingdom. His grip on reality is less reliable. He speaks regularly to someone he calls 'the Cartographer,' who no one else can see or hear.",
        "motivation" =>
          "Complete his life's work: the definitive map of every level beneath Thornwall.",
        "secret" =>
          "The Cartographer is real — the ghost of Thornwall's original builder, bound to the stones. It's been guiding Aldric deeper. Its motives are not scholarly. It wants to be found.",
        "relationships" => %{
          "court_mage" =>
            "Lysara's primary research partner. She asks about history; he asks about her visions. Neither tells the other everything.",
          "war_priest" =>
            "Maren thinks the Cartographer is a demon. Aldric thinks her faith is quaint. They argue constantly and are oddly fond of each other.",
          "shadow" =>
            "Treats Whisper as a useful source of artifacts from below. Doesn't care about Whisper's motives.",
          "patron" => "Corinne funds his research. He doesn't notice the strings attached."
        }
      },
      "patron" => %{
        "title" => "Noble Patron",
        "name" => "Lady Corinne Blackmere",
        "demeanor" =>
          "generous, sharp-eyed, regal bearing that doesn't quite hide the desperation underneath",
        "carries" => [
          "sealed letters",
          "signet ring",
          "vial of unknown medicine",
          "guard retinue she keeps at distance"
        ],
        "bot_assignments" => ["advocacy"],
        "backstory" =>
          "Noblewoman who funds expeditions into dangerous territory. Generous with gold, sharp with questions. The most powerful person in any room she enters — but power can't buy what she actually needs. Her family held Thornwall before the crown seized it. She wants it back, and not for pride.",
        "motivation" =>
          "Retrieve something from Thornwall's deepest level. She will not say what.",
        "secret" =>
          "She carries a bloodline curse — ancient, tied to whatever her ancestors built Thornwall to contain. She's slowly becoming something inhuman. The cure is in the deepest vault. Without it, she has months.",
        "relationships" => %{
          "tavern_keeper" =>
            "Brennan funds her expeditions. She accepts his gold and his grief. Both useful.",
          "shadow" =>
            "Employs Whisper for intelligence. Suspects Whisper's sibling found what Corinne is looking for — and that's why they never came back.",
          "sage" =>
            "Patronizes Aldric's research. His maps will lead her to the vault. He doesn't know why she really needs them.",
          "court_mage" =>
            "Lysara suspects her. Corinne respects the mage enough to be afraid of what she'll find."
        }
      }
    }
  end
end
