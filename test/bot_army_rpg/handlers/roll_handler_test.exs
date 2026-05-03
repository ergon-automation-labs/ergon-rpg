defmodule BotArmyRpg.Handlers.RollHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  describe "handle_roll/1" do
    test "rolls dice from notation" do
      message = %{"payload" => %{"notation" => "1d20+5"}}

      assert {:ok, result} = BotArmyRpg.Handlers.RollHandler.handle_roll(message)
      assert result["notation"] == "1d20+5"
      assert result["total"] >= 6 and result["total"] <= 25
      assert result["modifier"] == 5
    end

    test "returns error for missing notation" do
      message = %{"payload" => %{}}

      assert {:error, :notation_required} = BotArmyRpg.Handlers.RollHandler.handle_roll(message)
    end

    test "returns error for empty notation" do
      message = %{"payload" => %{"notation" => ""}}

      assert {:error, :notation_required} = BotArmyRpg.Handlers.RollHandler.handle_roll(message)
    end

    test "returns error for invalid notation" do
      message = %{"payload" => %{"notation" => "xyz"}}

      assert {:error, _} = BotArmyRpg.Handlers.RollHandler.handle_roll(message)
    end
  end
end
