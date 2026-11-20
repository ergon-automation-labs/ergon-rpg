defmodule BotArmyRpg.CharacterStoreTest do
  use ExUnit.Case, async: false
  @moduletag :stores

  alias BotArmyRpg.CharacterStore

  describe "a level-up boosts the class's primary ability, under either stat block" do
    @pathfinder %{
      "ability_scores" => %{
        "str" => 10,
        "dex" => 10,
        "int" => 10,
        "wis" => 10,
        "cha" => 10,
        "con" => 10
      },
      "xp" => 5
    }
    @cyberpunk %{
      "ability_scores" => %{
        "body" => 10,
        "ref" => 10,
        "tech" => 10,
        "net" => 10,
        "emp" => 10,
        "cool" => 10
      },
      "xp" => 5
    }

    defp boosted(stats, class), do: CharacterStore.boost_primary_ability(stats, class, 2)

    test "a pathfinder block keeps its own keys" do
      assert boosted(@pathfinder, "Oracle")["ability_scores"]["wis"] == 11
      assert boosted(@pathfinder, "Scheduler")["ability_scores"]["str"] == 11
      assert boosted(@pathfinder, "Fixer")["ability_scores"]["cha"] == 11
      assert boosted(@pathfinder, "Shapeshifter")["ability_scores"]["dex"] == 11
      assert boosted(@pathfinder, "Scribe")["ability_scores"]["int"] == 11
    end

    test "a cyberpunk block is boosted under its own names, with no stray pathfinder key" do
      oracle = boosted(@cyberpunk, "Oracle")["ability_scores"]
      assert oracle["net"] == 11
      refute Map.has_key?(oracle, "wis")

      scheduler = boosted(@cyberpunk, "Scheduler")["ability_scores"]
      assert scheduler["body"] == 11
      refute Map.has_key?(scheduler, "str")

      assert boosted(@cyberpunk, "Face")["ability_scores"]["emp"] == 11
      assert boosted(@cyberpunk, "Fixer")["ability_scores"]["emp"] == 11
      assert boosted(@cyberpunk, "Shapeshifter")["ability_scores"]["ref"] == 11
      assert boosted(@cyberpunk, "Scribe")["ability_scores"]["tech"] == 11
    end

    test "only the primary ability moves, and the rest of the sheet is kept" do
      after_boost = boosted(@cyberpunk, "Oracle")
      assert after_boost["xp"] == 5

      unchanged = Map.delete(after_boost["ability_scores"], "net")
      assert unchanged == Map.delete(@cyberpunk["ability_scores"], "net")
    end
  end

  # The handlers used to call this module's own client functions (get_by_user_id/2 and
  # update/3 are GenServer.call/3 into the process running the handler). OTP detects that and
  # exits with :calling_self, so the store died on every award and the caller got a crash
  # instead of a refusal - which is what rpg.character.award_xp answered on the live wire.
  describe "an award that finds nobody" do
    test "is a refusal for a user, and the store survives it" do
      start_supervised!(CharacterStore)
      pid = Process.whereis(CharacterStore)

      assert {:error, :character_not_found} = CharacterStore.award_xp("tenant", "nobody", 10)
      assert Process.whereis(CharacterStore) == pid
    end

    test "is a refusal for a bot, and the store survives it" do
      start_supervised!(CharacterStore)
      pid = Process.whereis(CharacterStore)

      assert {:error, :character_not_found} =
               CharacterStore.award_xp_to_bot("tenant", "nobody_bot", 10)

      assert Process.whereis(CharacterStore) == pid
    end

    test "an item for nobody is also a refusal the store survives" do
      start_supervised!(CharacterStore)
      pid = Process.whereis(CharacterStore)

      assert {:error, :character_not_found} =
               CharacterStore.add_item("tenant", "nobody", %{"name" => "a rock"})

      assert Process.whereis(CharacterStore) == pid
    end
  end

  describe "apply_xp/4 - the one curve" do
    test "below the bar, only the XP moves" do
      assert {2, 100} = CharacterStore.apply_xp(2, 0, 1000, 100)
    end

    test "reaching the bar exactly levels up with nothing carried" do
      assert {3, 0} = CharacterStore.apply_xp(2, 900, 1000, 100)
    end

    test "crossing the bar carries the remainder" do
      assert {3, 300} = CharacterStore.apply_xp(2, 900, 1000, 400)
    end

    test "one award earns one level, however large the award" do
      assert {3, 6000} = CharacterStore.apply_xp(2, 0, 1000, 7000)
    end

    test "the next bar is the level times five hundred" do
      assert 1000 == CharacterStore.xp_to_next(2)
      assert 1500 == CharacterStore.xp_to_next(3)
    end
  end
end
