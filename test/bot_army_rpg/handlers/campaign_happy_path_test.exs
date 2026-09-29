defmodule BotArmyRpg.Handlers.CampaignHappyPathTest do
  @moduledoc """
  The campaign handler's happy paths, with no database anywhere.

  `CampaignHandler` used to name `CampaignStore`, `XpEventStore` and
  `CampaignRosterStore` directly, which made every success path unreachable from a test:
  the stores are not started in the test environment, so the first store call exits. The
  handler now resolves each store through `Application.get_env/3` at call time, so these
  tests can hand it a mock and read what it actually asked for.

  What is pinned here is not "the store was called" but the *shape of the question* (the
  attributes an insert carries) and the one piece of real arithmetic in the handler: the
  scorecard's per-actor XP totals and reason-code histogram, which `rpg.campaign.close`
  builds from the ledger it read.
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.CampaignHandler

  @project "00000000-0000-0000-0000-0000000000p1"
  @campaign "00000000-0000-0000-0000-0000000000c1"
  @tenant "00000000-0000-0000-0000-000000000001"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :campaign_store, BotArmyRpg.CampaignStoreMock)
    Application.put_env(:bot_army_rpg, :xp_event_store, BotArmyRpg.XpEventStoreMock)

    Application.put_env(
      :bot_army_rpg,
      :campaign_roster_store,
      BotArmyRpg.CampaignRosterStoreMock
    )

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :campaign_store)
      Application.delete_env(:bot_army_rpg, :xp_event_store)
      Application.delete_env(:bot_army_rpg, :campaign_roster_store)
    end)

    :ok
  end

  test "start inserts a campaign for the project it was given" do
    expect(BotArmyRpg.CampaignStoreMock, :handle_insert, fn attrs ->
      send(self(), {:inserted, attrs})
      {:ok, %{"id" => @campaign, "gtd_project_id" => @project}}
    end)

    assert {:ok, %{"id" => @campaign}} =
             CampaignHandler.handle_start(%{
               "tenant_id" => @tenant,
               "gtd_project_id" => @project,
               "theme_snapshot" => %{"setting" => "Liberty City"}
             })

    assert_received {:inserted, attrs}
    assert attrs["gtd_project_id"] == @project
    assert attrs["tenant_id"] == @tenant
    assert attrs["theme_snapshot"] == %{"setting" => "Liberty City"}
    assert %DateTime{} = attrs["started_at"]
  end

  test "get finds a campaign by project, and says so when there is none" do
    expect(BotArmyRpg.CampaignStoreMock, :handle_get_by_project, fn @project ->
      %{"id" => @campaign, "status" => "active"}
    end)

    assert {:ok, %{"id" => @campaign}} =
             CampaignHandler.handle_get(%{"gtd_project_id" => @project})

    expect(BotArmyRpg.CampaignStoreMock, :handle_get_by_project, fn _ -> nil end)

    assert {:error, "campaign_not_found"} =
             CampaignHandler.handle_get(%{"gtd_project_id" => @project})
  end

  test "get finds a campaign by its own id" do
    expect(BotArmyRpg.CampaignStoreMock, :handle_get_by_id, fn @campaign ->
      %{"id" => @campaign, "status" => "active"}
    end)

    assert {:ok, %{"status" => "active"}} =
             CampaignHandler.handle_get(%{"rpg_campaign_id" => @campaign})
  end

  test "close reads the ledger and reports what the campaign actually did" do
    expect(BotArmyRpg.CampaignStoreMock, :handle_get_by_id, fn @campaign ->
      %{"id" => @campaign, "started_at" => "2026-01-01T00:00:00Z", "ended_at" => nil}
    end)

    # The real store replies with a bare list (`{:reply, filtered, state}`), not an
    # `{:ok, events}` tuple — a fixture that differs from the wire is a lie, and this one
    # was caught by the very test that used it.
    expect(BotArmyRpg.XpEventStoreMock, :handle_get_events, fn @campaign ->
      [
        %{"actor_id" => "a1", "delta" => 100, "reason_code" => "quest"},
        %{"actor_id" => "a1", "delta" => 50, "reason_code" => "roleplay"},
        %{"actor_id" => "a2", "delta" => -20, "reason_code" => "quest"}
      ]
    end)

    expect(BotArmyRpg.CampaignStoreMock, :handle_update, fn @campaign, attrs ->
      assert attrs.status == "completed"
      assert %DateTime{} = attrs.ended_at
      {:ok, %{"id" => @campaign, "status" => "completed"}}
    end)

    assert {:ok, closed} = CampaignHandler.handle_close(%{"rpg_campaign_id" => @campaign})

    scorecard = closed["scorecard"]
    assert scorecard["event_count"] == 3
    assert scorecard["actors"]["a1"] == %{"total_xp" => 150, "event_count" => 2}
    assert scorecard["actors"]["a2"] == %{"total_xp" => -20, "event_count" => 1}
    assert scorecard["reason_codes"] == %{"quest" => 2, "roleplay" => 1}
    assert scorecard["date_range"]["started_at"] == "2026-01-01T00:00:00Z"
  end

  test "close on a campaign that does not exist is refused before the ledger is read" do
    # No XpEventStoreMock expectation: reading the ledger for a campaign that is not there
    # would be an unexpected call, and the test would fail on it.
    stub(BotArmyRpg.CampaignStoreMock, :handle_get_by_id, fn _ -> nil end)

    assert {:error, "campaign_not_found"} =
             CampaignHandler.handle_close(%{"rpg_campaign_id" => @campaign})
  end

  test "the roster is read and written for one campaign" do
    expect(BotArmyRpg.CampaignRosterStoreMock, :handle_get_roster, fn @campaign ->
      [%{"npc_slug" => "the-innkeeper", "display_name" => "Mira"}]
    end)

    assert {:ok, %{"roster" => [%{"npc_slug" => "the-innkeeper"}]}} =
             CampaignHandler.handle_roster_get(%{"rpg_campaign_id" => @campaign})

    expect(BotArmyRpg.CampaignRosterStoreMock, :handle_upsert, fn @campaign, slug, attrs ->
      send(self(), {:upserted, slug, attrs})
      {:ok, %{"npc_slug" => slug}}
    end)

    assert {:ok, %{"npc_slug" => "the-innkeeper"}} =
             CampaignHandler.handle_roster_update(%{
               "rpg_campaign_id" => @campaign,
               "npc_slug" => "the-innkeeper",
               "display_name" => "Mira",
               "tenant_id" => @tenant
             })

    assert_received {:upserted, "the-innkeeper", attrs}
    assert attrs["display_name"] == "Mira"
    assert %DateTime{} = attrs["joined_at"]
    refute Map.has_key?(attrs, "left_at")
  end

  test "adding XP writes one ledger event carrying the reason it was given" do
    expect(BotArmyRpg.XpEventStoreMock, :handle_insert, fn attrs ->
      send(self(), {:event, attrs})
      {:ok, %{"id" => "event-1"}}
    end)

    assert {:ok, %{"id" => "event-1"}} =
             CampaignHandler.handle_xp_add(%{
               "rpg_campaign_id" => @campaign,
               "actor_kind" => "player",
               "actor_id" => "a1",
               "delta" => 25,
               "reason_code" => "roleplay"
             })

    assert_received {:event, attrs}
    assert attrs["rpg_campaign_id"] == @campaign
    assert attrs["actor_kind"] == "player"
    assert attrs["actor_id"] == "a1"
    assert attrs["delta"] == 25
    assert attrs["reason_code"] == "roleplay"
  end

  describe "rpg.campaign.xp_ledger" do
    test "no filters are asked for when none were given" do
      expect(BotArmyRpg.XpEventStoreMock, :handle_get_events, fn @campaign, filters ->
        # Mox matches the argument exactly, so a `%{actor_kind: nil}` here would fail.
        assert filters == %{}

        [
          %{"actor_id" => "a1", "delta" => 100, "reason_code" => "quest"},
          %{"actor_id" => "a1", "delta" => 25, "reason_code" => "roleplay"}
        ]
      end)

      assert {:ok, %{"events" => events, "per_actor" => per_actor}} =
               CampaignHandler.handle_xp_ledger(%{"rpg_campaign_id" => @campaign})

      assert length(events) == 2
      assert per_actor["a1"] == %{"total_xp" => 125, "event_count" => 2}
    end

    test "filters reach the store in the store's own vocabulary" do
      # The store reads `Map.get(filters, :actor_kind)` — atom keys. A caller-side string
      # key would be a silently ignored filter, so the vocabulary is pinned here.
      expect(BotArmyRpg.XpEventStoreMock, :handle_get_events, fn @campaign, filters ->
        assert filters == %{actor_kind: "player", actor_id: "a1"}
        []
      end)

      assert {:ok, %{"events" => [], "per_actor" => %{}}} =
               CampaignHandler.handle_xp_ledger(%{
                 "rpg_campaign_id" => @campaign,
                 "actor_kind" => "player",
                 "actor_id" => "a1"
               })
    end

    test "a filter present with a nil value is still passed on" do
      # Presence decides, not truthiness (`Map.has_key?/2`): the nil reaches the store,
      # whose own clause treats it as no filter at all.
      expect(BotArmyRpg.XpEventStoreMock, :handle_get_events, fn @campaign, filters ->
        assert filters == %{actor_kind: nil}
        []
      end)

      assert {:ok, %{"events" => []}} =
               CampaignHandler.handle_xp_ledger(%{
                 "rpg_campaign_id" => @campaign,
                 "actor_kind" => nil
               })
    end
  end
end
