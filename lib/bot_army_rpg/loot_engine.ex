defmodule BotArmyRpg.LootEngine do
  @moduledoc """
  Generates random loot based on source (quest, workout, lesson) and priority/difficulty.

  Rarity distribution: common 60%, uncommon 25%, rare 10%, epic 4%, legendary 1%.
  Item pools vary by source type.
  """

  @doc """
  Generate a random loot item.

  Returns a map: `{id, name, rarity, modifiers, source}` or nil if generation fails.
  """
  def generate(source, priority_or_intensity) when is_binary(source) do
    rarity = roll_rarity(priority_or_intensity)
    item_name = pick_item(source, rarity)

    if item_name do
      %{
        "id" => "item:#{source}:#{UUID.uuid4()}",
        "name" => item_name,
        "rarity" => rarity,
        "modifiers" => modifiers_for_rarity(rarity),
        "equipped" => false,
        "source" => source,
        "priority" => priority_or_intensity
      }
    else
      nil
    end
  end

  def generate(_source, _priority) do
    nil
  end

  # Roll rarity 0-100, with intensity bonus shifting distribution upward
  defp roll_rarity(priority_or_intensity) do
    roll = Enum.random(1..100) + intensity_bonus(priority_or_intensity)

    cond do
      roll <= 60 -> "common"
      roll <= 85 -> "uncommon"
      roll <= 95 -> "rare"
      roll <= 99 -> "epic"
      true -> "legendary"
    end
  end

  defp intensity_bonus(priority) when priority in ["high", "urgent"], do: 10
  defp intensity_bonus(intensity) when is_integer(intensity) and intensity >= 7, do: 15
  defp intensity_bonus(intensity) when is_integer(intensity) and intensity >= 4, do: 5
  defp intensity_bonus(_), do: 0

  # Pick item name based on source and rarity
  defp pick_item("gtd_task", rarity) do
    weapons = %{
      "common" => ["Wooden Sword", "Iron Dagger", "Leather Armor"],
      "uncommon" => ["Steel Sword", "Bronze Shield", "Chainmail"],
      "rare" => ["Mithril Blade", "Enchanted Robes", "Dragon Scale Armor"],
      "epic" => ["Legendary Sword", "Holy Armor", "Artifact Cloak"],
      "legendary" => ["Excalibur", "Plate of Gods", "Infinity Edge"]
    }

    weapons
    |> Map.get(rarity, ["Gold Coins"])
    |> Enum.random()
  end

  defp pick_item("fitness_workout", rarity) do
    items = %{
      "common" => ["Health Potion", "Strength Draught", "Protein Powder"],
      "uncommon" => ["Greater Potion", "Strength Ring", "Training Manual"],
      "rare" => ["Superior Elixir", "Ring of Strength +2", "Master's Tome"],
      "epic" => ["Legendary Draught", "Ring of Strength +5", "Artifact Codex"],
      "legendary" => ["Potion of Immortality", "Ring of Champions", "Book of Perfect Form"]
    }

    items
    |> Map.get(rarity, ["Health Potion"])
    |> Enum.random()
  end

  defp pick_item("learning_lesson", rarity) do
    items = %{
      "common" => ["Spell Scroll", "Grimoire Page", "Knowledge Crystal"],
      "uncommon" => ["Minor Spell Tome", "Intelligence Ring", "Codex Fragment"],
      "rare" => ["Advanced Grimoire", "Ring of Intellect +2", "Ancient Manuscript"],
      "epic" => ["Legendary Spell Book", "Ring of Wisdom +5", "Artifact Archive"],
      "legendary" => ["Tome of Infinite Knowledge", "Ring of Omniscience", "Forbidden Grimoire"]
    }

    items
    |> Map.get(rarity, ["Spell Scroll"])
    |> Enum.random()
  end

  defp pick_item(_source, rarity) do
    common_items = %{
      "common" => ["Gold Coins", "Potion", "Scroll"],
      "uncommon" => ["Silver Coins", "Greater Potion", "Rare Scroll"],
      "rare" => ["Gem", "Enchanted Amulet", "Ancient Scroll"],
      "epic" => ["Precious Jewel", "Legendary Amulet", "Artifact Scroll"],
      "legendary" => ["Crown Jewel", "Relic Amulet", "Forbidden Scroll"]
    }

    common_items
    |> Map.get(rarity, ["Gold Coins"])
    |> Enum.random()
  end

  # Modifiers based on rarity
  defp modifiers_for_rarity("common"), do: %{"attack" => 1}
  defp modifiers_for_rarity("uncommon"), do: %{"attack" => 2, "defense" => 1}
  defp modifiers_for_rarity("rare"), do: %{"attack" => 3, "defense" => 2, "magic" => 1}
  defp modifiers_for_rarity("epic"), do: %{"attack" => 5, "defense" => 3, "magic" => 2}
  defp modifiers_for_rarity("legendary"), do: %{"attack" => 10, "defense" => 5, "magic" => 5}
  defp modifiers_for_rarity(_), do: %{}
end
