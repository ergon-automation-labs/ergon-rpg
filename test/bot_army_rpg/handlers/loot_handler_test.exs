defmodule BotArmyRpg.Handlers.LootHandlerTest do
  @moduledoc """
  Loot is random by design, so what is pinned is not *which* item came back.

  `rpg.loot.generate` had no test. The engine rolls a rarity and picks from a table, so the
  item name is not a contract — but the *shape* is, and so is the answer for every input
  that has no table behind it. Two measured facts are pinned here rather than assumed: a
  source the engine cannot place is *not* refused (there is a generic fallback table), and
  only a source that is not a string at all reaches the failure answer.
  """

  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyRpg.Handlers.LootHandler

  test "a known source always yields a well-formed item" do
    for _ <- 1..5 do
      assert {:ok, loot} =
               LootHandler.handle_generate(%{"source" => "gtd_task", "priority" => "urgent"})

      assert is_binary(loot["name"])
      assert loot["source"] == "gtd_task"
      assert loot["priority"] == "urgent"
      assert loot["rarity"] in ~w(common uncommon rare epic legendary)
      assert loot["equipped"] == false
      assert is_map(loot["modifiers"])
      assert is_binary(loot["id"])
    end
  end

  test "an empty payload asks for the default source, and still gets a defined answer" do
    assert {:ok, loot} = LootHandler.handle_generate(%{})
    assert loot["source"] == "gtd_task"
    assert loot["priority"] == "normal"
  end

  test "an unknown source gets a generic item, and the item claims that source" do
    # Measured: the engine has no refusal path for a source it cannot place — its last
    # clause picks from a generic table — and the loot is labelled with whatever source
    # string arrived. So `source` on an item is the caller's word, not the engine's.
    assert {:ok, loot} = LootHandler.handle_generate(%{"source" => "no_such_source"})
    assert is_binary(loot["name"])
    assert loot["source"] == "no_such_source"
  end

  test "a source that is not a string is refused" do
    assert {:error, :loot_generation_failed} = LootHandler.handle_generate(%{"source" => 42})
  end
end
