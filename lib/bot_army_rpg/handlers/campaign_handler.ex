defmodule BotArmyRpg.Handlers.CampaignHandler do
  @moduledoc "Handles NATS messages for campaign start, update, and lifecycle."
  require Logger
  # Resolved at call time, not at compile time: a handler that names its store module
  # directly cannot be tested without a database.
  defp campaign_store do
    Application.get_env(:bot_army_rpg, :campaign_store, BotArmyRpg.CampaignStore)
  end

  defp xp_event_store do
    Application.get_env(:bot_army_rpg, :xp_event_store, BotArmyRpg.XpEventStore)
  end

  defp campaign_roster_store do
    Application.get_env(:bot_army_rpg, :campaign_roster_store, BotArmyRpg.CampaignRosterStore)
  end

  def handle_start(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || message["account_id"]

    gtd_project_id = params["gtd_project_id"]
    theme_snapshot = params["theme_snapshot"]

    with :ok <- validate_string(gtd_project_id, "uuid"),
         :ok <- validate_map(theme_snapshot),
         {:ok, campaign} <- insert_campaign(tenant_id, gtd_project_id, theme_snapshot) do
      {:ok, campaign}
    end
  end

  def handle_get(message) do
    params = message["payload"] || message

    case {params["gtd_project_id"], params["rpg_campaign_id"]} do
      {project_id, nil} when is_binary(project_id) ->
        case campaign_store().handle_get_by_project(project_id) do
          nil -> {:error, "campaign_not_found"}
          campaign -> {:ok, campaign}
        end

      {nil, campaign_id} when is_binary(campaign_id) ->
        case campaign_store().handle_get_by_id(campaign_id) do
          nil -> {:error, "campaign_not_found"}
          campaign -> {:ok, campaign}
        end

      _ ->
        {:error, "missing_gtd_project_id_or_rpg_campaign_id"}
    end
  end

  def handle_close(message) do
    params = message["payload"] || message
    rpg_campaign_id = params["rpg_campaign_id"]

    with :ok <- validate_string(rpg_campaign_id, "uuid"),
         {:ok, campaign} <- get_campaign(rpg_campaign_id),
         events <- xp_event_store().handle_get_events(rpg_campaign_id),
         scorecard <- build_scorecard(campaign, events),
         {:ok, updated} <-
           campaign_store().handle_update(rpg_campaign_id, %{
             status: "completed",
             ended_at: DateTime.utc_now()
           }) do
      {:ok, Map.put(updated, "scorecard", scorecard)}
    end
  end

  def handle_roster_get(message) do
    params = message["payload"] || message
    rpg_campaign_id = params["rpg_campaign_id"]

    with :ok <- validate_string(rpg_campaign_id, "uuid") do
      roster = campaign_roster_store().handle_get_roster(rpg_campaign_id)
      {:ok, %{"roster" => roster}}
    end
  end

  def handle_roster_update(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || message["account_id"]
    rpg_campaign_id = params["rpg_campaign_id"]
    npc_slug = params["npc_slug"]
    display_name = params["display_name"]

    with :ok <- validate_string(rpg_campaign_id, "uuid"),
         :ok <- validate_string(npc_slug, "slug"),
         :ok <- validate_string(display_name, "string") do
      attrs =
        %{
          "tenant_id" => tenant_id,
          "display_name" => display_name,
          "joined_at" => DateTime.utc_now()
        }
        |> then(fn a ->
          if Map.has_key?(params, "left_at"),
            do: Map.put(a, "left_at", params["left_at"]),
            else: a
        end)

      campaign_roster_store().handle_upsert(rpg_campaign_id, npc_slug, attrs)
    end
  end

  def handle_xp_add(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || message["account_id"]
    rpg_campaign_id = params["rpg_campaign_id"]
    actor_kind = params["actor_kind"]
    actor_id = params["actor_id"]
    delta = params["delta"]
    reason_code = params["reason_code"]

    with :ok <- validate_string(rpg_campaign_id, "uuid"),
         :ok <- validate_inclusion(actor_kind, ["player", "npc"], "actor_kind"),
         :ok <- validate_string(actor_id, "string"),
         :ok <- validate_integer(delta),
         :ok <- validate_string(reason_code, "string") do
      attrs = %{
        "rpg_campaign_id" => rpg_campaign_id,
        "actor_kind" => actor_kind,
        "actor_id" => actor_id,
        "delta" => delta,
        "reason_code" => reason_code,
        "tenant_id" => tenant_id
      }

      xp_event_store().handle_insert(attrs)
    end
  end

  def handle_xp_ledger(message) do
    params = message["payload"] || message
    rpg_campaign_id = params["rpg_campaign_id"]

    filters =
      %{}
      |> then(fn f ->
        if Map.has_key?(params, "actor_kind"),
          do: Map.put(f, :actor_kind, params["actor_kind"]),
          else: f
      end)
      |> then(fn f ->
        if Map.has_key?(params, "actor_id"),
          do: Map.put(f, :actor_id, params["actor_id"]),
          else: f
      end)

    with :ok <- validate_string(rpg_campaign_id, "uuid") do
      events = xp_event_store().handle_get_events(rpg_campaign_id, filters)
      {:ok, %{"events" => events, "per_actor" => rollup_by_actor(events)}}
    end
  end

  # Private helpers

  defp insert_campaign(tenant_id, gtd_project_id, theme_snapshot) do
    attrs = %{
      "tenant_id" => tenant_id,
      "gtd_project_id" => gtd_project_id,
      "theme_snapshot" => theme_snapshot,
      "started_at" => DateTime.utc_now()
    }

    campaign_store().handle_insert(attrs)
  end

  defp get_campaign(rpg_campaign_id) do
    case campaign_store().handle_get_by_id(rpg_campaign_id) do
      nil -> {:error, "campaign_not_found"}
      campaign -> {:ok, campaign}
    end
  end

  defp build_scorecard(campaign, events) do
    reason_codes =
      events
      |> Enum.reduce(%{}, fn event, acc ->
        code = event["reason_code"]
        Map.update(acc, code, 1, &(&1 + 1))
      end)

    %{
      "date_range" => %{
        "started_at" => campaign["started_at"],
        "ended_at" => campaign["ended_at"]
      },
      "actors" => rollup_by_actor(events),
      "event_count" => length(events),
      "reason_codes" => reason_codes
    }
  end

  # The domain is in the field name; the check is only "a string". Nothing here validates a
  # uuid or a slug *shape* - an empty string passes - so a malformed id travels to the store
  # and comes back as the store's own answer ("not found") instead of a refusal. This check
  # used to be three copies named `validate_uuid/1`, `validate_slug/1` and
  # `validate_string/1`; the first two promised a shape check that was never made. Enforcing
  # a shape is a decision with wire consequences, so it belongs to whoever makes it - not to
  # a function name that quietly assumes it.
  defp validate_string(nil, field), do: {:error, "missing_#{field}"}
  defp validate_string(val, _field) when is_binary(val), do: :ok
  defp validate_string(_val, field), do: {:error, "invalid_#{field}"}

  defp validate_integer(nil), do: {:error, "missing_integer"}
  defp validate_integer(val) when is_integer(val), do: :ok
  defp validate_integer(_), do: {:error, "invalid_integer"}

  defp validate_map(nil), do: {:error, "missing_map"}
  defp validate_map(val) when is_map(val), do: :ok
  defp validate_map(_), do: {:error, "invalid_map"}

  # The field name carries the domain here too, so a refusal names the value that was wrong
  # ("actor_kind") instead of the generic "invalid_value" - and a *missing* one is reported as
  # missing rather than as invalid.
  defp validate_inclusion(nil, _list, field), do: {:error, "missing_#{field}"}

  defp validate_inclusion(val, list, field) do
    if val in list, do: :ok, else: {:error, "invalid_#{field}"}
  end

  # One rollup, two wire fields: `rpg.campaign.close` reports this map as "actors" and
  # `rpg.campaign.xp_ledger` as "per_actor". The arithmetic used to exist twice — two
  # chances to drift — so there is now one copy. Tests pin both field names, so a change
  # that breaks either one has to break a test first.
  defp rollup_by_actor(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      actor_id = event["actor_id"]
      delta = event["delta"]

      Map.update(acc, actor_id, %{"total_xp" => delta, "event_count" => 1}, fn actor ->
        %{
          "total_xp" => actor["total_xp"] + delta,
          "event_count" => actor["event_count"] + 1
        }
      end)
    end)
  end
end
