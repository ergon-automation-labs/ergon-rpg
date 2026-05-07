defmodule BotArmyRpg.Handlers.SessionHandlerBotTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.SessionHandler

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :character_store)
    end)

    :ok
  end

  test "join allows bot-owned character for any user" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    character_id = "00000000-0000-0000-0000-0000000000dd"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get, fn ^tenant, ^character_id ->
      {:ok,
       %{
         "id" => character_id,
         "bot_id" => "gtd_bot",
         "tenant_id" => tenant
       }}
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
                                                        %{"character_ids" => ids} ->
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

    assert {:ok, _} = SessionHandler.handle_join(msg)
  end
end
