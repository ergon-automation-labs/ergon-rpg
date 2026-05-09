defmodule BotArmyRpg.ModifierEngine do
  @moduledoc """
  Calculates and applies item modifiers to character stats.

  Equipped items have modifiers (e.g., {"str": 2, "defense": 1}) that
  boost character ability scores and derived stats. This engine:
  - Collects all equipped items for a character
  - Sums their modifiers by stat
  - Returns total modifiers + final stats
  """

  @doc """
  Calculate total modifiers from equipped items.

  Returns: %{
    "modifiers" => %{"str" => 2, "dex" => 1, ...},
    "equipped_items" => [...items...]
  }
  """
  def calculate_modifiers(inventory) when is_map(inventory) do
    equipped = Map.get(inventory, "equipped", %{})
    items = Map.get(inventory, "items", [])

    equipped_items =
      equipped
      |> Enum.map(fn {_slot, item_id} ->
        Enum.find(items, &(Map.get(&1, "id") == item_id))
      end)
      |> Enum.filter(&(not is_nil(&1)))

    modifiers =
      equipped_items
      |> Enum.reduce(%{}, fn item, acc ->
        item_mods = Map.get(item, "modifiers", %{})
        merge_modifiers(acc, item_mods)
      end)

    %{
      "modifiers" => modifiers,
      "equipped_items" => equipped_items
    }
  end

  @doc """
  Apply modifiers to base ability scores.

  Returns: %{"str" => 12, "dex" => 11, ...} (base + modifiers)
  """
  def apply_modifiers(base_scores, modifiers) when is_map(base_scores) and is_map(modifiers) do
    base_scores
    |> Enum.into(%{}, fn {stat, base} ->
      mod = Map.get(modifiers, stat, 0)
      {stat, base + mod}
    end)
  end

  @doc """
  Get total ability scores for a character (base + equipped modifiers).
  """
  def get_total_scores(character) when is_map(character) do
    stats = Map.get(character, "stats", %{})
    base_scores = Map.get(stats, "ability_scores", %{})
    inventory = Map.get(character, "inventory", %{})

    %{"modifiers" => modifiers} = calculate_modifiers(inventory)
    apply_modifiers(base_scores, modifiers)
  end

  @doc """
  Get modifier summary for a character (for display).

  Returns: %{
    "total_modifiers" => %{"str" => 2, "dex" => 1},
    "equipped_count" => 2,
    "items" => [...equipped item names...]
  }
  """
  def get_modifier_summary(character) when is_map(character) do
    inventory = Map.get(character, "inventory", %{})
    %{"modifiers" => mods, "equipped_items" => items} = calculate_modifiers(inventory)

    %{
      "total_modifiers" => mods,
      "equipped_count" => Enum.count(items),
      "items" => Enum.map(items, &Map.get(&1, "name", "Unknown"))
    }
  end

  defp merge_modifiers(acc, item_mods) do
    Enum.reduce(item_mods, acc, fn {stat, value}, merged ->
      current = Map.get(merged, stat, 0)
      Map.put(merged, stat, current + value)
    end)
  end
end
