defmodule BotArmyRpg.Handlers.PartyHandlerTest do
  @moduledoc """
  The three things a party call can do, and what each one refuses.

  The party read has three answers and they are not the same answer: a party, **no
  party yet** (which says so, and is not the same as a party with nobody in it), and
  **a party that could not be read** (which is a refusal — an unreported party has to
  look unreported, never empty).
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.PartyHandler
  alias BotArmyRpg.NATS.Consumer

  @tenant "00000000-0000-0000-0000-000000000099"
  @user "00000000-0000-0000-0000-0000000000aa"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :party_store)
      Application.delete_env(:bot_army_rpg, :character_store)
    end)

    :ok
  end

  defp party_with(members) do
    %{"name" => "The Adventuring Party", "members" => members}
  end

  describe "handle_get/1" do
    test "reads the party, and takes each member's name, level and stats from the character store" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:ok, party_with([%{"bot_id" => "gtd_bot", "name" => "stale", "class" => "Scheduler"}])}
      end)

      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "gtd_bot" ->
        {:ok, %{"name" => "The Lorekeeper", "level" => 4, "stats" => %{"wit" => 3}}}
      end)

      assert {:ok, party} =
               PartyHandler.handle_get(%{"tenant_id" => @tenant, "user_id" => @user})

      assert [member] = party["members"]
      assert member["name"] == "The Lorekeeper"
      assert member["level"] == 4
      assert member["stats"] == %{"wit" => 3}
    end

    test "a member whose character cannot be read stays in the party, under the name we already have" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:ok, party_with([%{"bot_id" => "ghost_bot", "name" => "The Unread", "class" => "?"}])}
      end)

      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "ghost_bot" ->
        {:error, :not_found}
      end)

      assert {:ok, party} =
               PartyHandler.handle_get(%{"tenant_id" => @tenant, "user_id" => @user})

      assert [member] = party["members"]
      assert member["name"] == "The Unread"
    end

    test "an identity with no party yet is told so, and is not handed an empty party as if it were hers" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:error, :not_found}
      end)

      assert {:ok, party} =
               PartyHandler.handle_get(%{"tenant_id" => @tenant, "user_id" => @user})

      assert party["members"] == []
      assert party["message"] =~ "No party yet"
      assert party["name"] == "The Adventuring Party"
    end

    test "the way out it names is a route that answers" do
      # This message used to point at `rpg.party.auto_populate`, which is implemented but
      # deliberately not registered: an instruction that led nowhere, in the one place a
      # caller has nothing else to go on. The route it names has to be one that answers.
      Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:error, :not_found}
      end)

      assert {:ok, party} =
               PartyHandler.handle_get(%{"tenant_id" => @tenant, "user_id" => @user})

      assert party["message"] =~ "rpg.party.add"
      refute party["message"] =~ "auto_populate"

      registered = Consumer.subjects() |> Enum.map(& &1.subject)
      assert "rpg.party.add" in registered
      refute "rpg.party.auto_populate" in registered
    end

    test "a party that could not be read is refused, not answered with an empty party" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        {:error, :party_unreadable}
      end)

      assert {:error, :party_unreadable} =
               PartyHandler.handle_get(%{"tenant_id" => @tenant, "user_id" => @user})
    end

    test "a call that names no identity is refused" do
      assert {:error, :missing_user_id} = PartyHandler.handle_get(%{"tenant_id" => @tenant})
    end
  end

  describe "handle_set_narrator/1" do
    test "names the narrator through the store, and answers with the party that write produced" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :set_narrator, fn @tenant, @user, "char-gtd_bot" ->
        {:ok,
         party_with([
           %{"bot_id" => "gtd_bot", "character_id" => "char-gtd_bot", "role" => "narrator"}
         ])}
      end)

      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "gtd_bot" ->
        {:error, :not_found}
      end)

      assert {:ok, party} =
               PartyHandler.handle_set_narrator(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "character_id" => "char-gtd_bot"
               })

      assert [member] = party["members"]
      assert member["role"] == "narrator"
    end

    test "an explicit null clears the role; an absent character_id is a different request" do
      # Two requests that look alike and are not: `nil` is how a caller clears the role,
      # and a missing key is a caller who forgot to name anyone.
      assert {:error, :missing_character_id} =
               PartyHandler.handle_set_narrator(%{"tenant_id" => @tenant, "user_id" => @user})

      Mox.expect(BotArmyRpg.PartyStoreMock, :set_narrator, fn @tenant, @user, nil ->
        {:ok, party_with([%{"bot_id" => "gtd_bot", "role" => "companion"}])}
      end)

      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "gtd_bot" ->
        {:error, :not_found}
      end)

      assert {:ok, %{"members" => [%{"role" => "companion"}]}} =
               PartyHandler.handle_set_narrator(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "character_id" => nil
               })
    end

    test "a member the party does not have is refused, not quietly ignored" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :set_narrator, fn @tenant, @user, "char-ghost" ->
        {:error, :not_a_member}
      end)

      assert {:error, :not_a_member} =
               PartyHandler.handle_set_narrator(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "character_id" => "char-ghost"
               })
    end

    test "a call that names no identity is refused" do
      assert {:error, :missing_user_id} =
               PartyHandler.handle_set_narrator(%{"tenant_id" => @tenant, "character_id" => nil})
    end
  end

  describe "handle_add/1" do
    test "recruits a bot companion and answers with the party it joined" do
      character = %{
        "id" => "char-gtd_bot",
        "bot_id" => "gtd_bot",
        "name" => "The Lorekeeper",
        "class" => "Scheduler",
        "race" => "Construct",
        "level" => 1,
        "stats" => %{"wit" => 2}
      }

      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "gtd_bot" ->
        {:ok, character}
      end)

      Mox.expect(BotArmyRpg.PartyStoreMock, :add_member, fn @tenant, @user, member_data ->
        assert member_data["character_id"] == "char-gtd_bot"
        assert member_data["bot_id"] == "gtd_bot"
        {:ok, party_with([member_data])}
      end)

      # `enrich_party/2` reads the character back, so the party it answers with is
      # the one the character store can vouch for.
      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "gtd_bot" ->
        {:ok, character}
      end)

      assert {:ok, party} =
               PartyHandler.handle_add(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "bot_id" => "gtd_bot"
               })

      assert [member] = party["members"]
      assert member["name"] == "The Lorekeeper"
      assert member["stats"] == %{"wit" => 2}
    end

    test "a bot whose character cannot be provisioned is refused, with the reason" do
      Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn @tenant, "ghost_bot" ->
        {:error, :character_store_down}
      end)

      assert {:error, {:bot_character_failed, :character_store_down}} =
               PartyHandler.handle_add(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "bot_id" => "ghost_bot"
               })
    end

    test "a call naming no companion is refused" do
      assert {:error, :missing_bot_id} =
               PartyHandler.handle_add(%{"tenant_id" => @tenant, "user_id" => @user})
    end

    test "a call naming no identity is refused" do
      assert {:error, :missing_user_id} =
               PartyHandler.handle_add(%{"tenant_id" => @tenant, "bot_id" => "gtd_bot"})
    end
  end

  describe "handle_remove/1" do
    test "removes the companion through the store, and answers with the party that is left" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :remove_member, fn @tenant, @user, "char-gtd_bot" ->
        {:ok, party_with([])}
      end)

      assert {:ok, party} =
               PartyHandler.handle_remove(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "character_id" => "char-gtd_bot"
               })

      assert party["members"] == []
    end

    test "a removal the store refused is passed through as a refusal" do
      Mox.expect(BotArmyRpg.PartyStoreMock, :remove_member, fn @tenant, @user, "char-gtd_bot" ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} =
               PartyHandler.handle_remove(%{
                 "tenant_id" => @tenant,
                 "user_id" => @user,
                 "character_id" => "char-gtd_bot"
               })
    end

    test "a call naming no identity is refused" do
      assert {:error, :missing_user_id} =
               PartyHandler.handle_remove(%{
                 "tenant_id" => @tenant,
                 "character_id" => "char-gtd_bot"
               })
    end

    test "a call naming no companion is refused" do
      assert {:error, :missing_character_id} =
               PartyHandler.handle_remove(%{"tenant_id" => @tenant, "user_id" => @user})
    end
  end
end
