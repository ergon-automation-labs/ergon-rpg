defmodule BotArmyRpg.Handlers.SessionContextHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.SessionContextHandler

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
    end)

    :ok
  end

  test "gather_context returns full context when session_id provided" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    bot_id = "fitness_bot"

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "user_id" => user,
         "status" => "active",
         "scene_description" => "The training grounds at dawn",
         "metadata" => %{"mood" => "tense"}
       }}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, ^session_id ->
      {:ok,
       [
         %{
           "content" => "Drillmaster revealed the cache",
           "created_at" => "2026-05-10T12:00:00"
         },
         %{
           "content" => "Rain began falling on the harbor",
           "created_at" => "2026-05-10T11:00:00"
         }
       ]}
    end)

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:ok,
       %{
         "id" => "char-1",
         "name" => "The Drillmaster",
         "race" => "Half-Orc",
         "class" => "Drillmaster"
       }}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant ->
      {:ok, %{"setting" => "cyberpunk", "tone" => "hopeful"}}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "bot_id" => bot_id
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == session_id
    assert context["session_status"] == "active"
    assert context["scene_description"] == "The training grounds at dawn"
    assert context["character"]["name"] == "The Drillmaster"
    assert context["theme"]["setting"] == "cyberpunk"
    assert length(context["scene_facts"]) == 2
    assert "Drillmaster revealed the cache" in context["scene_facts"]
  end

  test "gather_context finds active session by user_id when session_id omitted" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok,
       [
         %{
           "id" => session_id,
           "tenant_id" => tenant,
           "user_id" => user,
           "status" => "active",
           "scene_description" => "The harbor at night"
         },
         %{
           "id" => "other-id",
           "tenant_id" => tenant,
           "user_id" => user,
           "status" => "ended",
           "scene_description" => "Old session"
         }
       ]}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, ^session_id ->
      {:ok, []}
    end)

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, _ ->
      {:error, :not_found}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant ->
      {:error, :not_found}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "bot_id" => "fitness_bot"
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == session_id
    assert context["session_status"] == "active"
    assert context["character"] == %{}
    assert context["theme"] == %{}
    assert context["scene_facts"] == []
  end

  test "gather_context returns error when no active session found" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok,
       [
         %{
           "id" => "ended-id",
           "tenant_id" => tenant,
           "user_id" => user,
           "status" => "ended",
           "scene_description" => "Old session"
         }
       ]}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user
      }
    }

    assert {:error, :no_active_session} = SessionContextHandler.handle_gather_context(msg)
  end

  test "gather_context returns error when provided session_id is not active" do
    tenant = "00000000-0000-0000-0000-000000000099"
    session_id = "00000000-0000-0000-0000-0000000000cc"

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "status" => "paused",
         "scene_description" => "Paused session"
       }}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => "any-user",
        "session_id" => session_id
      }
    }

    assert {:error, :session_not_active} = SessionContextHandler.handle_gather_context(msg)
  end
end
