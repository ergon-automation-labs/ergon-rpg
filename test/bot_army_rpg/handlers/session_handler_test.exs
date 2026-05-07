defmodule BotArmyRpg.Handlers.SessionHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.SessionHandler

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
    end)

    :ok
  end

  test "join updates character_ids when owner matches and session active" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    character_id = "00000000-0000-0000-0000-0000000000dd"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get, fn ^tenant, ^character_id ->
      {:ok, %{"id" => character_id, "user_id" => user, "tenant_id" => tenant}}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "status" => "active",
         "character_ids" => %{}
       }}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :update, fn ^tenant,
                                                        ^session_id,
                                                        %{
                                                          "character_ids" => ids
                                                        } ->
      assert ids[character_id] == user
      {:ok, %{"id" => session_id, "character_ids" => ids, "status" => "active"}}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "character_id" => character_id
      }
    }

    assert {:ok, %{"character_ids" => joined}} = SessionHandler.handle_join(msg)
    assert joined[character_id] == user
  end

  test "join forbidden when character owned by another user" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    other = "00000000-0000-0000-0000-0000000000bb"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    character_id = "00000000-0000-0000-0000-0000000000dd"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get, fn ^tenant, ^character_id ->
      {:ok, %{"id" => character_id, "user_id" => other, "tenant_id" => tenant}}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "character_id" => character_id
      }
    }

    assert {:error, :forbidden} = SessionHandler.handle_join(msg)
  end

  test "leave removes character when user matches participant map" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    character_id = "00000000-0000-0000-0000-0000000000dd"

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "status" => "active",
         "character_ids" => %{character_id => user}
       }}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :update, fn ^tenant,
                                                        ^session_id,
                                                        %{
                                                          "character_ids" => ids
                                                        } ->
      assert ids == %{}
      {:ok, %{"id" => session_id, "character_ids" => ids, "status" => "active"}}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "character_id" => character_id
      }
    }

    assert {:ok, _} = SessionHandler.handle_leave(msg)
  end

  test "leave returns not_joined when character not in session" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    character_id = "00000000-0000-0000-0000-0000000000dd"

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "status" => "active",
         "character_ids" => %{}
       }}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "character_id" => character_id
      }
    }

    assert {:error, :not_joined} = SessionHandler.handle_leave(msg)
  end
end
