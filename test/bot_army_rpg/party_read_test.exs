defmodule BotArmyRpg.PartyReadTest do
  @moduledoc """
  What a party read answers — and what it refuses to answer.

  `nil` is not a key any store answers for, so a character with no user must not reach the
  store at all; `:not_found` is an answer (this identity has no party) rather than a
  refusal; and anything else is carried to the caller, because a store that could not
  answer is not a party with no members.
  """

  use ExUnit.Case
  @moduletag :core

  import Mox

  alias BotArmyRpg.PartyRead

  @tenant "00000000-0000-0000-0000-000000000001"
  @user "00000000-0000-0000-0000-000000000002"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStoreMock)

    on_exit(fn -> Application.delete_env(:bot_army_rpg, :party_store) end)

    :ok
  end

  describe "read/2" do
    test "no user is no party, and the store is never asked a question it cannot key" do
      # No expectation, no stub: a call here would raise out of the mock.
      assert {:ok, %{}} = PartyRead.read(@tenant, nil)
    end

    test "a store that holds no party answers with an empty party, not a refusal" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:error, :not_found}
      end)

      assert {:ok, %{}} = PartyRead.read(@tenant, @user)
    end

    test "a party comes back as the store gave it" do
      party = %{"members" => [%{"character_id" => "c1", "role" => "narrator"}]}

      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user -> {:ok, party} end)

      assert {:ok, ^party} = PartyRead.read(@tenant, @user)
    end

    test "a store that refuses is carried, not read as an empty party" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = PartyRead.read(@tenant, @user)
    end

    test "a user that is not a key at all is no party" do
      assert {:ok, %{}} = PartyRead.read(@tenant, 42)
    end
  end

  describe "shape/1" do
    test "reduces a reason to its kind, so a log line never carries the key" do
      assert PartyRead.shape({:calling_self, "00000000-0000-0000-0000-000000000002"}) ==
               :calling_self

      assert PartyRead.shape(:timeout) == :timeout
      assert PartyRead.shape(%{detail: "x"}) == %{detail: "x"}
    end
  end
end
