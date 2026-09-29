defmodule BotArmyRpg.Progression.CompanionsTest.DeadStore do
  @moduledoc false

  # Deliberately not a running process: the point is the exit, not the answer.
  def list(_tenant_id), do: GenServer.call(:bot_army_rpg_no_such_store, :list)
end

defmodule BotArmyRpg.Progression.CompanionsTest do
  use ExUnit.Case, async: false
  @moduletag :core

  alias BotArmyRpg.CharacterStoreMock
  alias BotArmyRpg.Progression.Companions

  import Mox

  setup :verify_on_exit!

  # This key is not set by config/test.exs; each test starts without it so the fallback is
  # the fallback, and the knob is put back immediately rather than on exit.
  setup do
    Application.delete_env(:bot_army_rpg, :away_xp_rate)
    :ok
  end

  @tenant "00000000-0000-0000-0000-000000000001"
  @participant %{"id" => "p-1", "user_id" => "u-1", "level" => 2}
  @companion %{
    "id" => "c-1",
    "bot_id" => "bard_bot",
    "name" => "The Bard",
    "level" => 3,
    "stats" => %{}
  }

  describe "share/2" do
    test "a half by default, and the share stays an integer" do
      assert 50 == Companions.share(100, 0.5)
      assert 25 == Companions.share(100, 0.25)
      assert 33 == Companions.share(67, 0.5)
    end

    test "a companion's share is always smaller than the award it shadows" do
      for xp <- [1, 10, 99, 100, 250, 5000], rate <- [0.0, 0.25, 0.5, 0.99] do
        assert Companions.share(xp, rate) < xp
      end
    end

    test "nothing is earned from a non-positive or non-numeric award" do
      assert 0 == Companions.share(0, 0.5)
      assert 0 == Companions.share(-50, 0.5)
      assert 0 == Companions.share("100", 0.5)
      assert 0 == Companions.share(100, "a lot")
    end
  end

  describe "away_rate/0" do
    test "reads the knob" do
      Application.put_env(:bot_army_rpg, :away_xp_rate, 0.25)
      assert 0.25 == Companions.away_rate()
      Application.delete_env(:bot_army_rpg, :away_xp_rate)
    end

    test "falls back loudly on a rate that could out-pace the award" do
      Application.put_env(:bot_army_rpg, :away_xp_rate, 1.5)

      log = ExUnit.CaptureLog.capture_log(fn -> assert 0.5 == Companions.away_rate() end)
      assert log =~ "unusable away_xp_rate"
      Application.delete_env(:bot_army_rpg, :away_xp_rate)
    end
  end

  describe "targets/2" do
    test "everyone but the character who was actually there" do
      others = [@companion, %{"id" => "c-2", "bot_id" => "innkeeper_bot"}]
      assert Companions.targets([@participant | others], @participant) == others
    end
  end

  describe "award_away/3" do
    test "awards every companion, and never the character who was there" do
      innkeeper = %{"id" => "c-2", "bot_id" => "innkeeper_bot", "name" => "The Innkeeper"}

      expect(CharacterStoreMock, :list, fn @tenant ->
        {:ok, [@participant, @companion, innkeeper]}
      end)

      expect(CharacterStoreMock, :award_xp_to_bot, fn @tenant, "bard_bot", 50 ->
        {:ok, Map.put(@companion, "stats", %{"xp" => 50, "xp_to_next" => 1500})}
      end)

      expect(CharacterStoreMock, :award_xp_to_bot, fn @tenant, "innkeeper_bot", 50 ->
        {:ok, Map.put(innkeeper, "stats", %{"xp" => 50, "xp_to_next" => 500})}
      end)

      # No expectation for the participant: awarding them here would be an unexpected call.
      assert [_bard, _innkeeper] =
               away(@tenant, @participant, 100, publish: fn _, _ -> :ok end)
    end

    test "honours an explicit rate" do
      expect(CharacterStoreMock, :list, fn @tenant -> {:ok, [@companion]} end)

      expect(CharacterStoreMock, :award_xp_to_bot, fn @tenant, "bard_bot", 25 ->
        {:ok, Map.put(@companion, "stats", %{"xp" => 25})}
      end)

      assert [_] =
               away(@tenant, @participant, 100,
                 rate: 0.25,
                 publish: fn _, _ -> :ok end
               )
    end

    test "a share that rounds away never reaches the store" do
      # No expectations at all: any call to the store here is an unexpected call.
      assert 0 == away(@tenant, @participant, 100, rate: 0.0)
    end

    test "a companion the store cannot find is skipped, not fatal" do
      expect(CharacterStoreMock, :list, fn @tenant -> {:ok, [@companion]} end)

      expect(CharacterStoreMock, :award_xp_to_bot, fn @tenant, "bard_bot", 50 ->
        {:error, :character_not_found}
      end)

      assert [] ==
               away(@tenant, @participant, 100, publish: fn _, _ -> :ok end)
    end

    test "a store that refuses to list leaves the rest of the progression alone" do
      expect(CharacterStoreMock, :list, fn @tenant -> {:error, :database_unavailable} end)

      assert [] == away(@tenant, @participant, 100)
    end

    test "a store that is not there does not take the caller down" do
      # Passed in, not put in the application environment: other test modules delete that
      # key on exit, so reading the ambient default makes this file order-dependent.
      assert [] == away(@tenant, @participant, 100, store: __MODULE__.DeadStore)
    end

    test "the away notification says it was away" do
      expect(CharacterStoreMock, :list, fn @tenant -> {:ok, [@companion]} end)

      expect(CharacterStoreMock, :award_xp_to_bot, fn @tenant, "bard_bot", 50 ->
        {:ok, Map.put(@companion, "stats", %{"xp" => 50, "xp_to_next" => 1500})}
      end)

      me = self()

      assert [_] =
               away(@tenant, @participant, 100,
                 publish: fn tenant_id, payload -> send(me, {:away, tenant_id, payload}) end
               )

      assert_received {:away, @tenant,
                       %{"away" => true, "xp_earned" => 50, "character_name" => "The Bard"}}
    end
  end

  # Every award names its store. Other test modules do
  # `Application.put_env(:character_store, Mock)` in setup and `delete_env` on exit, which
  # removes the key config/test.exs set - so a test that reads the ambient default resolves
  # the real, unstarted store once those modules have run, and passes or fails by module
  # order. Naming the store makes this file order-independent.
  defp away(tenant_id, participant, xp_amount, opts \\ []) do
    Companions.award_away(
      tenant_id,
      participant,
      xp_amount,
      Keyword.put_new(opts, :store, CharacterStoreMock)
    )
  end
end
