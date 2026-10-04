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

    test "a name is keyed the way the routes key it, not asked of the store as a name" do
      # The dashboard recruits a party under the name an operator uses for herself, and
      # `Identity.resolve_user_id/2` hashes that into the UUID the column holds. A read
      # that handed the store the name would ask for a row no row is stored under.
      keyed = BotArmyRpg.Identity.normalize_user_id("abby")
      refute keyed == "abby"

      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, ^keyed ->
        {:ok, %{"members" => []}}
      end)

      assert {:ok, %{"members" => []}} = PartyRead.read(@tenant, "abby")
    end
  end

  describe "narrator/2" do
    test "names the member who narrates" do
      narrator = %{
        "character_id" => "c-narrator",
        "bot_id" => "companion_bot",
        "role" => "narrator"
      }

      member = %{"character_id" => "c-member", "bot_id" => "gtd_bot", "role" => "companion"}

      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:ok, %{"members" => [member, narrator]}}
      end)

      assert {:ok, ^narrator} = PartyRead.narrator(@tenant, @user)
    end

    test "a party with no narrator names nobody, and that is an answer" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:ok, %{"members" => [%{"character_id" => "c1", "role" => "companion"}]}}
      end)

      assert {:ok, nil} = PartyRead.narrator(@tenant, @user)
    end

    test "no party names nobody" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user -> {:error, :not_found} end)

      assert {:ok, nil} = PartyRead.narrator(@tenant, @user)
    end

    test "an identity with no user names nobody, and the store is never asked" do
      assert {:ok, nil} = PartyRead.narrator(@tenant, nil)
    end

    test "a store that refuses is carried, not read as a party with no narrator" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user -> {:error, :timeout} end)

      assert {:error, :timeout} = PartyRead.narrator(@tenant, @user)
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
