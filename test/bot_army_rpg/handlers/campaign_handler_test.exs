defmodule BotArmyRpg.Handlers.CampaignHandlerTest do
  @moduledoc """
  What a campaign call refuses, before it is allowed to touch a store.

  Seven live subjects (`rpg.campaign.*`) had **no test at all** until now, and there is a
  reason for that: every one of them names its store module directly
  (`CampaignStore.handle_get_by_id/1`, …), so no test can stand in for the database and
  the happy paths are unreachable. What *is* reachable is the part that matters most for
  a bot that dies the moment a handler raises: **validation runs before the store**, so
  junk on the wire has to come back as a named refusal rather than an exception.

  That is the property these tests pin, and they are deliberately store-free. If one of
  them ever reaches a store it will fail visibly (no Repo process, no GenServer) rather
  than quietly — which is the signal that the validation order changed. The honest
  limitation is recorded with the follow-up: the happy paths wait for the seam, because
  a mock cannot be told what an insert returns until these stores have behaviours and
  are resolved at call time.
  """

  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyRpg.Handlers.CampaignHandler

  @uuid "00000000-0000-0000-0000-0000000000c1"

  describe "an empty payload on every live campaign route" do
    test "all seven refuse instead of raising" do
      # Every route the Consumer dispatches for campaigns, with nothing in the payload.
      # A raise here is the failure mode that silences the whole bot (see the handler-raise
      # runbook), so each of these calls is standing in for a caller that sent junk.
      answers = [
        CampaignHandler.handle_start(%{}),
        CampaignHandler.handle_get(%{}),
        CampaignHandler.handle_close(%{}),
        CampaignHandler.handle_roster_get(%{}),
        CampaignHandler.handle_roster_update(%{}),
        CampaignHandler.handle_xp_add(%{}),
        CampaignHandler.handle_xp_ledger(%{})
      ]

      assert length(answers) == 7
      assert Enum.all?(answers, &match?({:error, _}, &1))
    end
  end

  describe "rpg.campaign.start" do
    test "a project id that is not a string is not a project" do
      assert {:error, "invalid_uuid"} = CampaignHandler.handle_start(%{"gtd_project_id" => 42})
    end

    test "a theme snapshot that is missing is refused as missing" do
      assert {:error, "missing_map"} =
               CampaignHandler.handle_start(%{"gtd_project_id" => @uuid})
    end

    test "a theme snapshot that is not a map is refused as invalid, before the store" do
      # `with` short-circuits, so the *second* failure being the one reported proves the
      # first two checks are a gate and not a decoration.
      assert {:error, "invalid_map"} =
               CampaignHandler.handle_start(%{
                 "gtd_project_id" => @uuid,
                 "theme_snapshot" => ["not", "a", "map"]
               })
    end

    test "a payload nested under \"payload\" is read the same way" do
      assert {:error, "missing_uuid"} =
               CampaignHandler.handle_start(%{"payload" => %{"theme_snapshot" => %{}}})
    end
  end

  describe "rpg.campaign.get" do
    test "neither id is a question this route can answer" do
      assert {:error, "missing_gtd_project_id_or_rpg_campaign_id"} =
               CampaignHandler.handle_get(%{})
    end

    test "both ids at once is also a refusal, not a silent preference" do
      # The route answers `{project_id, nil}` or `{nil, campaign_id}`. Two ids is a caller
      # that does not know which campaign it means, so it is refused rather than guessed
      # at — the same refusal string, which is the honest report of "not answerable".
      assert {:error, "missing_gtd_project_id_or_rpg_campaign_id"} =
               CampaignHandler.handle_get(%{
                 "gtd_project_id" => @uuid,
                 "rpg_campaign_id" => @uuid
               })
    end

    test "a non-string project id does not fall into the id branch" do
      assert {:error, "missing_gtd_project_id_or_rpg_campaign_id"} =
               CampaignHandler.handle_get(%{"gtd_project_id" => 12_345})
    end
  end

  describe "rpg.campaign.roster.update" do
    test "a roster row with no campaign is refused first" do
      assert {:error, "missing_uuid"} = CampaignHandler.handle_roster_update(%{})
    end

    test "an npc with no slug is refused before the string check" do
      assert {:error, "missing_slug"} =
               CampaignHandler.handle_roster_update(%{"rpg_campaign_id" => @uuid})
    end

    test "a slug with no display name is refused" do
      assert {:error, "missing_string"} =
               CampaignHandler.handle_roster_update(%{
                 "rpg_campaign_id" => @uuid,
                 "npc_slug" => "sable"
               })
    end
  end

  describe "rpg.campaign.xp.add" do
    test "an actor kind outside player/npc is refused, and the refusal names the field" do
      # This used to answer the generic "invalid_value", which tells a caller nothing about
      # which value was wrong. The field name travels with the check now.
      assert {:error, "invalid_actor_kind"} =
               CampaignHandler.handle_xp_add(%{
                 "rpg_campaign_id" => @uuid,
                 "actor_kind" => "goblin",
                 "actor_id" => @uuid,
                 "delta" => 5,
                 "reason_code" => "quest"
               })
    end

    test "a missing actor kind is refused as missing, not as invalid" do
      assert {:error, "missing_actor_kind"} =
               CampaignHandler.handle_xp_add(%{
                 "rpg_campaign_id" => @uuid,
                 "actor_id" => @uuid,
                 "delta" => 5,
                 "reason_code" => "quest"
               })
    end

    test "a delta that is a string is not a delta" do
      assert {:error, "invalid_integer"} =
               CampaignHandler.handle_xp_add(%{
                 "rpg_campaign_id" => @uuid,
                 "actor_kind" => "player",
                 "actor_id" => @uuid,
                 "delta" => "5",
                 "reason_code" => "quest"
               })
    end

    test "a missing delta is refused as missing, not as invalid" do
      # Absence and wrongness are different answers everywhere else in this bot; the
      # validators keep them apart here too.
      assert {:error, "missing_integer"} =
               CampaignHandler.handle_xp_add(%{
                 "rpg_campaign_id" => @uuid,
                 "actor_kind" => "player",
                 "actor_id" => @uuid,
                 "reason_code" => "quest"
               })
    end

    test "a negative delta is a legitimate correction, not junk" do
      # XP that cannot be taken back is not a ledger, it is a score. The proof that the
      # value passed validation is that execution reached the store — which, in this
      # suite, is not running, so the call exits. That exit *is* the assertion: a
      # refusal would have come back as a tuple long before it.
      assert :reached_the_store =
               outcome(fn ->
                 CampaignHandler.handle_xp_add(%{
                   "rpg_campaign_id" => @uuid,
                   "actor_kind" => "player",
                   "actor_id" => @uuid,
                   "delta" => -5,
                   "reason_code" => "correction"
                 })
               end)
    end

    test "an actor id that is not a string is refused" do
      assert {:error, "invalid_string"} =
               CampaignHandler.handle_xp_add(%{
                 "rpg_campaign_id" => @uuid,
                 "actor_kind" => "npc",
                 "actor_id" => 99,
                 "delta" => 5,
                 "reason_code" => "quest"
               })
    end
  end

  describe "rpg.campaign.xp.ledger, rpg.campaign.close, rpg.campaign.roster.get" do
    test "a ledger for no campaign is refused" do
      assert {:error, "missing_uuid"} = CampaignHandler.handle_xp_ledger(%{})
    end

    test "closing nothing is refused" do
      assert {:error, "missing_uuid"} = CampaignHandler.handle_close(%{})
    end

    test "reading the roster of nothing is refused" do
      assert {:error, "missing_uuid"} = CampaignHandler.handle_roster_get(%{})
    end
  end

  # When the seam lands (behaviours + call-time store resolution) the store answer
  # becomes a tuple and this helper stops being needed — one deliberate edit, not a
  # silent drift.
  defp outcome(fun) do
    fun.()
  catch
    :exit, _reason -> :reached_the_store
  end

  describe "the tenant question (recorded, not decided here)" do
    test "no campaign route validates the tenant, unlike the party routes" do
      # `handle_start` reads `tenant_id` and passes it straight into the insert attrs, and
      # the other six routes do the same, so a caller that never sent one would carry
      # `"tenant_id" => nil` into a write. The party routes refuse a missing actor
      # (`:missing_user_id`) and the roster route refuses a missing slug; nothing here
      # refuses a missing tenant. This test records the asymmetry so that closing it is a
      # deliberate change — and it stays store-free by construction, because the payload
      # is refused for the other reason.
      result = CampaignHandler.handle_start(%{"theme_snapshot" => %{}})

      assert {:error, reason} = result
      assert reason == "missing_uuid"
    end
  end
end
