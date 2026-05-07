defmodule BotArmyRpg.DefaultsTest do
  use ExUnit.Case
  @moduletag :core

  test "default_pathfinder_stats returns expected structure" do
    stats = BotArmyRpg.Defaults.default_pathfinder_stats()

    assert Map.has_key?(stats, "ability_scores")
    assert Map.has_key?(stats, "hp")
    assert Map.has_key?(stats, "ac")
    assert Map.has_key?(stats, "saves")
    assert Map.has_key?(stats, "skills")

    ability_scores = stats["ability_scores"]
    assert ability_scores["str"] == 10
    assert ability_scores["dex"] == 10
    assert ability_scores["con"] == 10
    assert ability_scores["int"] == 10
    assert ability_scores["wis"] == 10
    assert ability_scores["cha"] == 10

    assert stats["hp"]["current"] == 10
    assert stats["hp"]["max"] == 10
    assert stats["ac"] == 10
  end

  test "default_inventory returns expected structure" do
    inventory = BotArmyRpg.Defaults.default_inventory()

    assert Map.has_key?(inventory, "equipment")
    assert Map.has_key?(inventory, "gold")
    assert Map.has_key?(inventory, "items")
    assert inventory["gold"] == 0
  end

  test "bot_archetype returns known bot archetypes" do
    assert BotArmyRpg.Defaults.bot_archetype("gtd_bot") == %{race: "Human", class: "Scheduler"}
    assert BotArmyRpg.Defaults.bot_archetype("synapse") == %{race: "Elf", class: "Oracle"}
    assert BotArmyRpg.Defaults.bot_archetype("llm_bot") == %{race: "Tiefling", class: "Bard"}

    assert BotArmyRpg.Defaults.bot_archetype("sre_terminal") == %{
             race: "Dwarf",
             class: "Sentinel"
           }
  end

  test "bot_archetype normalizes bot_army_ prefix" do
    assert BotArmyRpg.Defaults.bot_archetype("bot_army_gtd") == %{
             race: "Human",
             class: "Scheduler"
           }

    assert BotArmyRpg.Defaults.bot_archetype(:bot_army_synapse) == %{race: "Elf", class: "Oracle"}
  end

  test "bot_archetype falls back to Adventurer for unknown bots" do
    assert BotArmyRpg.Defaults.bot_archetype("unknown") == %{race: "Unknown", class: "Adventurer"}
  end
end
