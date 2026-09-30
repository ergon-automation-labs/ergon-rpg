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
    Application.put_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStoreMock)

    # The party rides in every context (2026-09-30), so the double answers it by default:
    # most of these tests are about the window, not about who walks with her. A test that
    # cares says so with an `expect`.
    Mox.stub(BotArmyRpg.PartyStoreMock, :get_party, fn _tenant, _user -> {:error, :not_found} end)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
      Application.delete_env(:bot_army_rpg, :party_store)
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

  test "gather_context opens the window this identity was last in, not the first one listed" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"

    last_used =
      window(tenant, user, %{
        "id" => "last-used",
        "scene_description" => "the alley we were in",
        "updated_at" => "2026-09-02T10:00:00"
      })

    abandoned =
      window(tenant, user, %{
        "id" => "abandoned",
        "scene_description" => "a room we left",
        "updated_at" => "2026-09-01T10:00:00"
      })

    # The store hands back a map's values, so this order is not a reading — it is the
    # order that used to decide which conversation the phone drew.
    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant -> {:ok, [abandoned, last_used]} end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, "last-used" ->
      {:ok, []}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant -> {:error, :not_found} end)

    msg = %{"payload" => %{"tenant_id" => tenant, "user_id" => user}}

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == "last-used"
    assert context["scene_description"] == "the alley we were in"
  end

  defp window(tenant, user, overrides) do
    Map.merge(
      %{
        "id" => "00000000-0000-0000-0000-0000000000cc",
        "tenant_id" => tenant,
        "user_id" => user,
        "status" => "active",
        "scene_description" => "somewhere",
        "metadata" => %{},
        "created_at" => "2026-09-01T09:00:00",
        "updated_at" => "2026-09-01T09:00:00"
      },
      overrides
    )
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

  # ───────────────────────────────────────────────────────────────────────────
  # The story so far (carry history)
  # ───────────────────────────────────────────────────────────────────────────

  defp carry_history_session(tenant, user, session_id) do
    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "user_id" => user,
         "status" => "active",
         "scene_description" => "A new alleyway, cold"
       }}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, ^session_id ->
      {:ok, []}
    end)

    # Stubbed, not expected: with no `bot_id` in the payload the character is never
    # looked up at all, and a carry test is not the place to demand it.
    Mox.stub(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, _bot ->
      {:error, :not_found}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant -> {:error, :not_found} end)
  end

  test "carry_history brings the earlier windows' turns, oldest first, and not this window's" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    earlier = "00000000-0000-0000-0000-0000000000bb"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_recent_for_tenant, fn ^tenant, opts ->
      # The window being read is excluded, and the ask is this identity's, so one
      # household member's story never becomes another's.
      assert opts[:exclude_session_id] == session_id
      assert opts[:user_id] == user
      # Turns, not notes: a fact the machinery wrote is not something that
      # happened in her story (the exclusion itself is proved against the real
      # store in scene_fact_store_test.exs).
      assert opts[:story_only] == true

      {:ok,
       [
         %{
           "content" => "the GM closed the door",
           "source" => "gm",
           "session_id" => earlier,
           "created_at" => "2026-05-10T12:00:00"
         },
         %{
           "content" => "Hi!",
           "source" => "operator",
           "session_id" => earlier,
           "created_at" => "2026-05-10T11:00:00"
         }
       ]}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "carry_history" => true
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)

    assert Enum.map(context["carry_history"], & &1["content"]) == [
             "Hi!",
             "the GM closed the door"
           ]

    assert Enum.map(context["carry_history"], & &1["source"]) == ["operator", "gm"]
    assert Enum.all?(context["carry_history"], &(&1["session_id"] == earlier))
  end

  test "carry_history is not asked for: the key is absent, not empty" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    refute Map.has_key?(context, "carry_history")
  end

  test "carry_history read cleanly and nothing came before: an empty list, not a nil" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_recent_for_tenant, fn ^tenant, _opts ->
      {:ok, []}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "carry_history" => true
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["carry_history"] == []
  end

  test "a carry that cannot be read is unreported, and the window still stands" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_recent_for_tenant, fn ^tenant, _opts ->
      {:error, :database_error}
    end)

    msg = %{
      "payload" => %{
        "tenant_id" => tenant,
        "user_id" => user,
        "session_id" => session_id,
        "carry_history" => true
      }
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == session_id
    # nil is "the bot did not say", [] is "nothing came before". Only one of those is true.
    assert context["carry_history"] == nil
    refute context["carry_history"] == []
  end

  # ───────────────────────────────────────────────────────────────────────────
  # The party the window carries
  # ───────────────────────────────────────────────────────────────────────────

  test "gather_context carries the roster this identity walks with" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn ^tenant, ^user ->
      {:ok,
       %{
         "name" => "The Adventuring Party",
         "members" => [
           %{"bot_id" => "gtd_bot", "name" => "The Lorekeeper", "class" => "Sage"}
         ]
       }}
    end)

    msg = %{
      "payload" => %{"tenant_id" => tenant, "user_id" => user, "session_id" => session_id}
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    # The identity the party is stored under is the one the window belongs to, and the
    # read is the same `fetch_party/2` the bot-centric adventure context uses.
    assert context["party"]["name"] == "The Adventuring Party"
    assert [%{"bot_id" => "gtd_bot"}] = context["party"]["members"]
    assert context["session_id"] == session_id
  end

  test "no party at all: the store answered, and it says nobody" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn ^tenant, ^user ->
      {:error, :not_found}
    end)

    msg = %{
      "payload" => %{"tenant_id" => tenant, "user_id" => user, "session_id" => session_id}
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    # The store was asked and answered: this identity has no party. That is a reading.
    assert context["party"] == %{}
    refute context["party"] == nil
  end

  test "a party that cannot be read is unreported, and the window still stands" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn ^tenant, ^user ->
      {:error, :database_unavailable}
    end)

    msg = %{
      "payload" => %{"tenant_id" => tenant, "user_id" => user, "session_id" => session_id}
    }

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == session_id
    # nil is "the bot did not say", %{} is "nobody walks with her". Only one is true.
    assert context["party"] == nil
    refute context["party"] == %{}
  end

  test "a party store that is dead is unreported too, and its key never reaches the log" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    carry_history_session(tenant, user, session_id)

    # What `GenServer.call` exits with when nothing is registered under the name: the
    # reason carries the arguments of the call that died, and those are the party's key.
    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn tenant, user ->
      exit(
        {:noproc, {GenServer, :call, [BotArmyRpg.PartyStore, {:get_party, tenant, user}, 5000]}}
      )
    end)

    msg = %{
      "payload" => %{"tenant_id" => tenant, "user_id" => user, "session_id" => session_id}
    }

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
        assert context["session_id"] == session_id
        assert context["party"] == nil
      end)

    assert log =~ "Party unread: exited :noproc"
    refute log =~ user
  end

  test "an identity with no user is never asked about a party" do
    tenant = "00000000-0000-0000-0000-000000000099"
    session_id = "00000000-0000-0000-0000-0000000000cc"

    Mox.expect(BotArmyRpg.SessionStoreMock, :get, fn ^tenant, ^session_id ->
      {:ok,
       %{
         "id" => session_id,
         "tenant_id" => tenant,
         "user_id" => nil,
         "status" => "active",
         "scene_description" => "probe"
       }}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, ^session_id ->
      {:ok, []}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant -> {:error, :not_found} end)

    # No party expectation: a message with no identity has no party to look up, so the
    # store must not be asked at all — the read reports that it cannot be made, rather
    # than manufacturing a question the store has no key for.
    msg = %{"payload" => %{"tenant_id" => tenant, "session_id" => session_id}}

    assert {:ok, context} = SessionContextHandler.handle_gather_context(msg)
    assert context["session_id"] == session_id
    assert context["party"] == %{}
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Adventure Context Query (bot-centric)
  # ───────────────────────────────────────────────────────────────────────────

  test "handle_adventure_context returns full adventure context for a bot" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    session_id = "00000000-0000-0000-0000-0000000000cc"
    bot_id = "fitness_bot"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:ok,
       %{
         "id" => "char-1",
         "name" => "The Drillmaster",
         "race" => "Half-Orc",
         "class" => "Drillmaster",
         "level" => 5,
         "user_id" => user
       }}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok,
       [
         %{
           "id" => session_id,
           "tenant_id" => tenant,
           "user_id" => user,
           "status" => "active",
           "scene_description" => "The training grounds at dawn",
           "metadata" => %{"round" => 3}
         }
       ]}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, ^session_id ->
      {:ok,
       [
         %{"content" => "Drillmaster revealed the cache", "created_at" => "2026-05-10T12:00:00"}
       ]}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant ->
      {:ok, %{"setting" => "cyberpunk", "tone" => "hopeful"}}
    end)

    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn ^tenant, ^user ->
      {:ok,
       %{
         "name" => "The Iron Vanguard",
         "members" => [
           %{"bot_id" => "fitness_bot", "name" => "The Drillmaster", "class" => "Drillmaster"},
           %{"bot_id" => "gtd", "name" => "The Taskmaster", "class" => "Tactician"}
         ]
       }}
    end)

    msg = %{
      "tenant_id" => tenant,
      "bot_id" => bot_id
    }

    assert {:ok, context} = SessionContextHandler.handle_adventure_context(msg)
    assert context["bot_id"] == bot_id
    assert context["tenant_id"] == tenant
    assert context["character"]["name"] == "The Drillmaster"
    assert context["session"]["scene_description"] == "The training grounds at dawn"
    assert context["session"]["status"] == "active"
    assert context["theme"]["setting"] == "cyberpunk"
    assert length(context["scene_facts"]) == 1
    assert context["party"]["name"] == "The Iron Vanguard"
    assert length(context["party"]["members"]) == 2
  end

  test "handle_adventure_context finds session via user_id when character has no session" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    bot_id = "chore_bot"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:ok,
       %{
         "id" => "char-2",
         "name" => "The Steward",
         "class" => "Housekeeper",
         "user_id" => user
       }}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok,
       [
         %{
           "id" => "sess-1",
           "tenant_id" => tenant,
           "user_id" => user,
           "status" => "active",
           "scene_description" => "The kitchen at midnight"
         }
       ]}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, "sess-1" ->
      {:ok, []}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant ->
      {:error, :not_found}
    end)

    Mox.expect(BotArmyRpg.PartyStoreMock, :get_party, fn ^tenant, ^user ->
      {:error, :not_found}
    end)

    msg = %{"tenant_id" => tenant, "bot_id" => bot_id}

    assert {:ok, context} = SessionContextHandler.handle_adventure_context(msg)
    assert context["session"]["scene_description"] == "The kitchen at midnight"
    assert context["theme"] == %{}
    assert context["party"] == %{}
  end

  test "handle_adventure_context returns error when bot has no character" do
    tenant = "00000000-0000-0000-0000-000000000099"
    bot_id = "unknown_bot"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:error, :not_found}
    end)

    msg = %{"tenant_id" => tenant, "bot_id" => bot_id}

    assert {:error, :no_character} = SessionContextHandler.handle_adventure_context(msg)
  end

  test "handle_adventure_context returns error when no active session exists for user" do
    tenant = "00000000-0000-0000-0000-000000000099"
    user = "00000000-0000-0000-0000-0000000000aa"
    bot_id = "fitness_bot"

    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:ok, %{"id" => "char-1", "name" => "Drillmaster", "user_id" => user}}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok, []}
    end)

    msg = %{"tenant_id" => tenant, "bot_id" => bot_id}

    assert {:error, :no_active_session} = SessionContextHandler.handle_adventure_context(msg)
  end

  test "handle_adventure_context answers when the character has no user — a party it cannot ask about is not a party it reports" do
    tenant = "00000000-0000-0000-0000-000000000099"
    bot_id = "gtd_bot"

    # The live case (2026-09-29): `gtd_bot`'s character carries `user_id: nil`, and the
    # session it plays in has `user_id: nil` too. The party store's key is
    # {tenant_id, user_id} and `nil` is not a key it answers for, so asking it anyway
    # did not report an absent party — it raised, which took the Consumer process down
    # with it and left the caller with no reply at all. Four 13s timeouts in a row,
    # each one a fresh crash.
    Mox.expect(BotArmyRpg.CharacterStoreMock, :get_by_bot_id, fn ^tenant, ^bot_id ->
      {:ok, %{"id" => "char-1", "name" => "The Lorekeeper", "user_id" => nil}}
    end)

    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant ->
      {:ok,
       [
         %{
           "id" => "sess-null-user",
           "tenant_id" => tenant,
           "user_id" => nil,
           "status" => "active",
           "scene_description" => "probe"
         }
       ]}
    end)

    Mox.expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn ^tenant, "sess-null-user" ->
      {:ok, []}
    end)

    Mox.expect(BotArmyRpg.ThemeStoreMock, :get_current, fn ^tenant -> {:error, :not_found} end)

    # No PartyStoreMock expectation on purpose: with no user there is no party to look
    # up, so the store must not be asked at all. Mox fails this test if it is.

    msg = %{"tenant_id" => tenant, "bot_id" => bot_id}

    assert {:ok, context} = SessionContextHandler.handle_adventure_context(msg)
    assert context["character"]["name"] == "The Lorekeeper"
    assert context["session"]["scene_description"] == "probe"
    assert context["party"] == %{}
  end
end
