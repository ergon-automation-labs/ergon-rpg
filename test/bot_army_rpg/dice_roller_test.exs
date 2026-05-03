defmodule BotArmyRpg.DiceRollerTest do
  use ExUnit.Case
  @moduletag :core

  describe "roll/1" do
    test "rolls a single d20" do
      {:ok, result} = BotArmyRpg.DiceRoller.roll("d20")

      assert result["notation"] == "d20"
      assert result["total"] >= 1 and result["total"] <= 20
      assert length(result["rolls"]) == 1
      assert result["modifier"] == 0
    end

    test "rolls 2d6" do
      {:ok, result} = BotArmyRpg.DiceRoller.roll("2d6")

      assert result["notation"] == "2d6"
      assert result["total"] >= 2 and result["total"] <= 12
      assert length(result["rolls"]) == 1
      assert length(result["rolls"] |> hd() |> Map.get("rolls")) == 2
    end

    test "rolls 1d20+5 with positive modifier" do
      {:ok, result} = BotArmyRpg.DiceRoller.roll("1d20+5")

      assert result["notation"] == "1d20+5"
      assert result["total"] >= 6 and result["total"] <= 25
      assert result["modifier"] == 5
    end

    test "rolls 1d20-2 with negative modifier" do
      {:ok, result} = BotArmyRpg.DiceRoller.roll("1d20-2")

      assert result["notation"] == "1d20-2"
      assert result["total"] >= -1 and result["total"] <= 18
      assert result["modifier"] == -2
    end

    test "rolls 2d6+1d8+3 with multiple groups" do
      {:ok, result} = BotArmyRpg.DiceRoller.roll("2d6+1d8+3")

      assert result["notation"] == "2d6+1d8+3"
      assert length(result["rolls"]) == 2
      assert result["modifier"] == 3
    end

    test "returns error for invalid notation" do
      assert {:error, _} = BotArmyRpg.DiceRoller.roll("invalid")
    end

    test "returns error for empty string" do
      assert {:error, :empty_notation} = BotArmyRpg.DiceRoller.roll("")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_notation} = BotArmyRpg.DiceRoller.roll(123)
    end
  end

  describe "parse/1" do
    test "parses simple d20" do
      {:ok, groups, modifier} = BotArmyRpg.DiceRoller.parse("d20")

      assert groups == [%{count: 1, sides: 20}]
      assert modifier == 0
    end

    test "parses 3d8" do
      {:ok, groups, modifier} = BotArmyRpg.DiceRoller.parse("3d8")

      assert groups == [%{count: 3, sides: 8}]
      assert modifier == 0
    end

    test "parses modifier" do
      {:ok, _groups, modifier} = BotArmyRpg.DiceRoller.parse("1d20+5")
      assert modifier == 5
    end

    test "parses negative modifier" do
      {:ok, _groups, modifier} = BotArmyRpg.DiceRoller.parse("1d20-3")
      assert modifier == -3
    end
  end
end
