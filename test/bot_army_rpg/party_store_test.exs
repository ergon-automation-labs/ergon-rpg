defmodule BotArmyRpg.PartyStoreTest do
  @moduledoc """
  The party's decisions, without a database.

  `PartyStore` used to hold the party in its own state, and its own name for what it held
  was "the user's permanent adventuring group" — while a restart took every member with
  it. The memberships live in a table now, and the store still has to answer for three
  things a table does not decide for it:

    * what adding the same companion twice means (one of her),
    * when the party began (the oldest membership, not the moment of the read),
    * and what a failure is. A read that fails is `{:error, :database_unavailable}`, never
      "no party yet" — an unreported party may not look empty — and a write that fails
      leaves the party exactly as it was.

  A stand-in answers the party's table here (see `BotArmyRpg.Test.FakePartyRepo`); the same
  decisions against real Postgres are in `party_store_db_test.exs`.
  """

  use ExUnit.Case, async: false
  @moduletag :core

  alias BotArmyRpg.PartyStore
  alias BotArmyRpg.Test.FakePartyRepo

  @tenant "00000000-0000-0000-0000-000000000099"
  @user "00000000-0000-0000-0000-0000000000aa"

  @characters %{
    "gtd_bot" => "11111111-1111-1111-1111-111111111111",
    "llm_bot" => "22222222-2222-2222-2222-222222222222"
  }

  setup do
    FakePartyRepo.reset()
    start_supervised!({PartyStore, party_repo: FakePartyRepo})
    :ok
  end

  defp member(bot_id, overrides \\ %{}) do
    Map.merge(
      %{
        "character_id" => Map.fetch!(@characters, bot_id),
        "bot_id" => bot_id,
        "name" => "The #{bot_id}",
        "class" => "Companion",
        "race" => "Construct"
      },
      overrides
    )
  end

  test "an identity with no party is not found — 'no party yet' is not an empty party" do
    assert {:error, :not_found} = PartyStore.get_party(@tenant, @user)
  end

  test "a companion that joins is in the party, with when she joined" do
    assert {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert [joined] = party["members"]
    assert joined["bot_id"] == "gtd_bot"
    assert joined["name"] == "The gtd_bot"
    assert joined["class"] == "Companion"
    assert joined["role"] == "companion"
    assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(joined["joined_at"])
  end

  test "the party remembers the membership, not the character's level" do
    # Level changes, and the character store is its one live answer; a copy here would
    # be a second answer that goes stale quietly.
    {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot", %{"level" => 9}))

    assert [joined] = party["members"]
    refute Map.has_key?(joined, "level")
  end

  test "adding the same companion twice leaves one of her in the party" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert length(party["members"]) == 1
  end

  test "the party is still there after the store is restarted" do
    # The whole reason for the table: this store's process is not where the party lives.
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    stop_supervised!(PartyStore)

    start_supervised!({PartyStore, party_repo: FakePartyRepo})

    assert {:ok, party} = PartyStore.get_party(@tenant, @user)
    assert [joined] = party["members"]
    assert joined["bot_id"] == "gtd_bot"
    assert joined["name"] == "The gtd_bot"
  end

  test "the party's age is its oldest membership, not the moment of the read" do
    {:ok, first} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    created_at = first["created_at"]

    {:ok, after_second} = PartyStore.add_member(@tenant, @user, member("llm_bot"))
    assert after_second["created_at"] == created_at

    {:ok, after_read} = PartyStore.get_party(@tenant, @user)
    assert after_read["created_at"] == created_at
  end

  test "a companion that leaves is out of the party" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    {:ok, party} = PartyStore.remove_member(@tenant, @user, @characters["gtd_bot"])

    assert party["members"] == []
  end

  test "removing a companion from an identity with no party is refused" do
    assert {:error, :not_found} =
             PartyStore.remove_member(@tenant, @user, @characters["gtd_bot"])
  end

  test "listing a tenant's parties says which identity each party belongs to" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert {:ok, [party]} = PartyStore.list_parties(@tenant)
    assert party["user_id"] == @user
    assert length(party["members"]) == 1
  end

  describe "a database that is not answering" do
    test "a read that fails is a refusal, never 'no party yet'" do
      FakePartyRepo.break_reads()
      pid = Process.whereis(PartyStore)

      assert {:error, :database_unavailable} = PartyStore.get_party(@tenant, @user)
      assert Process.whereis(PartyStore) == pid
    end

    test "a listing that fails is a refusal too" do
      FakePartyRepo.break_reads()

      assert {:error, :database_unavailable} = PartyStore.list_parties(@tenant)
    end

    test "a write that fails is a refusal, and the party is as it was" do
      {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
      FakePartyRepo.break_writes()

      assert {:error, :database_unavailable} =
               PartyStore.add_member(@tenant, @user, member("llm_bot"))

      FakePartyRepo.mend()

      assert {:ok, party} = PartyStore.get_party(@tenant, @user)
      assert [%{"bot_id" => "gtd_bot"}] = party["members"]
    end

    test "a removal that fails is a refusal, and she stays in the party" do
      {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
      FakePartyRepo.break_writes()

      assert {:error, :database_unavailable} =
               PartyStore.remove_member(@tenant, @user, @characters["gtd_bot"])

      FakePartyRepo.mend()

      assert {:ok, party} = PartyStore.get_party(@tenant, @user)
      assert [%{"bot_id" => "gtd_bot"}] = party["members"]
    end
  end
end
