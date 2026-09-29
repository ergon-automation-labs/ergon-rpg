defmodule BotArmyRpg.CharacterStoreTest do
  use ExUnit.Case, async: false
  @moduletag :stores

  alias BotArmyRpg.CharacterStore

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
