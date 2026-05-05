defmodule BotArmyRpg.Handlers.RollHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyRpg.Handlers.RollHandler

  # Test doubles for the publisher

  defmodule SuccessfulPublisher do
    def request("bridge.random.roll", payload, _opts) do
      notation = payload["notation"]
      _seed = Map.get(payload, "seed")

      {:ok,
       %{
         "status" => "ok",
         "data" => %{
           "notation" => notation,
           "rolls" => [10],
           "groups" => [%{"count" => 1, "sides" => 20, "rolls" => [10], "subtotal" => 10}],
           "modifier" => 5,
           "total" => 15,
           "algo_version" => "2"
         }
       }}
    end

    def request(_subject, _payload, _opts) do
      {:error, :unknown_subject}
    end
  end

  defmodule FailingPublisher do
    def request(_subject, _payload, _opts) do
      {:error, :timeout}
    end
  end

  defmodule MultiGroupPublisher do
    def request("bridge.random.roll", payload, _opts) do
      notation = payload["notation"]

      {:ok,
       %{
         "status" => "ok",
         "data" => %{
           "notation" => notation,
           "rolls" => [3, 5, 7],
           "groups" => [
             %{"count" => 2, "sides" => 6, "rolls" => [3, 5], "subtotal" => 8},
             %{"count" => 1, "sides" => 8, "rolls" => [7], "subtotal" => 7}
           ],
           "modifier" => 3,
           "total" => 18,
           "algo_version" => "2"
         }
       }}
    end
  end

  describe "handle_roll/2 with bridge" do
    test "delegates to bridge and returns data" do
      message = %{"payload" => %{"notation" => "1d20+5"}}

      assert {:ok, data} = RollHandler.handle_roll(message, SuccessfulPublisher)
      assert data["notation"] == "1d20+5"
      assert data["total"] == 15
      assert data["modifier"] == 5
      assert data["algo_version"] == "2"
    end

    test "passes seed to bridge" do
      message = %{"payload" => %{"notation" => "1d20", "seed" => "test-seed"}}

      assert {:ok, data} = RollHandler.handle_roll(message, SuccessfulPublisher)
      assert data["notation"] == "1d20"
    end

    test "handles multi-group via bridge" do
      message = %{"payload" => %{"notation" => "2d6+1d8+3"}}

      assert {:ok, data} = RollHandler.handle_roll(message, MultiGroupPublisher)
      assert data["notation"] == "2d6+1d8+3"
      assert length(data["groups"]) == 2
      assert data["total"] == 18
    end

    test "falls back to local DiceRoller when bridge unavailable" do
      message = %{"payload" => %{"notation" => "1d20+5"}}

      assert {:ok, result} = RollHandler.handle_roll(message, FailingPublisher)
      # Local DiceRoller returns a different shape but still works
      assert result["notation"] == "1d20+5"
      assert is_integer(result["total"])
    end

    test "falls back to local DiceRoller for multi-group when bridge unavailable" do
      message = %{"payload" => %{"notation" => "2d6+1d8+3"}}

      assert {:ok, result} = RollHandler.handle_roll(message, FailingPublisher)
      assert result["notation"] == "2d6+1d8+3"
      assert is_integer(result["total"])
    end
  end

  describe "handle_roll/1 validation" do
    test "returns error for missing notation" do
      message = %{"payload" => %{}}
      assert {:error, :notation_required} = RollHandler.handle_roll(message)
    end

    test "returns error for empty notation" do
      message = %{"payload" => %{"notation" => ""}}
      assert {:error, :notation_required} = RollHandler.handle_roll(message)
    end

    test "returns error for invalid notation via fallback" do
      message = %{"payload" => %{"notation" => "xyz"}}
      # Falls back to DiceRoller which returns {:error, :no_dice_found}
      assert {:error, _} = RollHandler.handle_roll(message, FailingPublisher)
    end
  end
end
