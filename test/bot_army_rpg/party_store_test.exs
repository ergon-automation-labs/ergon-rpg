defmodule BotArmyRpg.PartyStoreTest do
  @moduledoc """
  The party itself: who is in it, and what adding someone twice means.

  `PartyStore` holds the party **in memory**. Its own name for what it holds is "the
  user's permanent adventuring group", and permanence is exactly what this store does
  not have: nothing below survives a restart, and no test here pretends otherwise. A
  table behind this store is the next thing the party feature needs — until then,
  "permanent" means "until the bot next starts".
  """

  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.PartyStore

  @tenant "00000000-0000-0000-0000-000000000099"
  @user "00000000-0000-0000-0000-0000000000aa"

  setup do
    start_supervised!(PartyStore)
    :ok
  end

  defp member(bot_id, overrides \\ %{}) do
    Map.merge(
      %{
        "character_id" => "char-#{bot_id}",
        "bot_id" => bot_id,
        "name" => "The #{bot_id}",
        "class" => "Companion"
      },
      overrides
    )
  end

  test "an identity with no party is not found — 'no party yet' is not an empty party" do
    assert {:error, :not_found} = PartyStore.get_party(@tenant, @user)
  end

  test "a companion that joins is in the party, with when it joined" do
    assert {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert [joined] = party["members"]
    assert joined["bot_id"] == "gtd_bot"
    assert joined["name"] == "The gtd_bot"
    assert joined["role"] == "companion"
    assert joined["level"] == 1
    assert is_binary(joined["joined_at"])
  end

  test "adding the same companion twice leaves one of it in the party" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert length(party["members"]) == 1
  end

  test "a companion that leaves is out of the party" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    {:ok, party} = PartyStore.remove_member(@tenant, @user, "char-gtd_bot")

    assert party["members"] == []
  end

  test "removing a companion from an identity with no party is refused" do
    assert {:error, :not_found} = PartyStore.remove_member(@tenant, @user, "char-gtd_bot")
  end

  test "listing a tenant's parties says which identity each party belongs to" do
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert {:ok, [party]} = PartyStore.list_parties(@tenant)
    assert party["user_id"] == @user
    assert length(party["members"]) == 1
  end
end
