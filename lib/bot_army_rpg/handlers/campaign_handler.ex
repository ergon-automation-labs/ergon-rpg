defmodule BotArmyRpg.Handlers.CampaignHandler do
  @moduledoc "Handles NATS messages for campaign start, update, and lifecycle."
  require Logger
  alias BotArmyRpg.{CampaignStore, XpEventStore, CampaignRosterStore}

  def handle_start(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || message["account_id"]

    gtd_project_id = params["gtd_project_id"]
    theme_snapshot = params["theme_snapshot"]

    with :ok <- validate_uuid(gtd_project_id),
         :ok <- validate_map(theme_snapshot),
         {:ok, campaign} <- insert_campaign(tenant_id, gtd_project_id, theme_snapshot) do
      {:ok, campaign}
    end
  end

  def handle_get(message) do
    params = message["payload"] || message

    case {params["gtd_project_id"], params["rpg_campaign_id"]} do
      {project_id, nil} when is_binary(project_id) ->
        case CampaignStore.handle_get_by_project(project_id) do
          nil -> {:error, "campaign_not_found"}
          campaign -> {:ok, campaign}
        end

      {nil, campaign_id} when is_binary(campaign_id) ->
        case CampaignStore.handle_get_by_id(campaign_id) do
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

    with :ok <- validate_uuid(rpg_campaign_id),
         {:ok, campaign} <- get_campaign(rpg_campaign_id),
         events <- XpEventStore.handle_get_events(rpg_campaign_id),
         scorecard <- build_scorecard(campaign, events),
         {:ok, updated} <-
           CampaignStore.handle_update(rpg_campaign_id, %{
             status: "completed",
             ended_at: DateTime.utc_now()
           }) do
      {:ok, Map.put(updated, "scorecard", scorecard)}
    end
  end

  def handle_roster_get(message) do
    params = message["payload"] || message
    rpg_campaign_id = params["rpg_campaign_id"]

    with :ok <- validate_uuid(rpg_campaign_id) do
      roster = CampaignRosterStore.handle_get_roster(rpg_campaign_id)
      {:ok, %{"roster" => roster}}
    end
  end

  def handle_roster_update(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || message["account_id"]
    rpg_campaign_id = params["rpg_campaign_id"]
    npc_slug = params["npc_slug"]
    display_name = params["display_name"]

    with :ok <- validate_uuid(rpg_campaign_id),
         :ok <- validate_slug(npc_slug),
         :ok <- validate_string(display_name) do
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

      CampaignRosterStore.handle_upsert(rpg_campaign_id, npc_slug, attrs)
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

    with :ok <- validate_uuid(rpg_campaign_id),
         :ok <- validate_inclusion(actor_kind, ["player", "npc"]),
         :ok <- validate_string(actor_id),
         :ok <- validate_integer(delta),
         :ok <- validate_string(reason_code) do
      attrs = %{
        "rpg_campaign_id" => rpg_campaign_id,
        "actor_kind" => actor_kind,
        "actor_id" => actor_id,
        "delta" => delta,
        "reason_code" => reason_code,
        "tenant_id" => tenant_id
      }

      XpEventStore.handle_insert(attrs)
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

    with :ok <- validate_uuid(rpg_campaign_id) do
      events = XpEventStore.handle_get_events(rpg_campaign_id, filters)

      per_actor =
        events
        |> Enum.reduce(%{}, fn event, acc ->
          actor_id = event["actor_id"]
          delta = event["delta"]

          Map.update(acc, actor_id, %{"total_xp" => delta, "event_count" => 1}, fn actor ->
            %{
              "total_xp" => actor["total_xp"] + delta,
              "event_count" => actor["event_count"] + 1
            }
          end)
        end)

      {:ok, %{"events" => events, "per_actor" => per_actor}}
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

    CampaignStore.handle_insert(attrs)
  end

  defp get_campaign(rpg_campaign_id) do
    case CampaignStore.handle_get_by_id(rpg_campaign_id) do
      nil -> {:error, "campaign_not_found"}
      campaign -> {:ok, campaign}
    end
  end

  defp build_scorecard(campaign, events) do
    per_actor =
      events
      |> Enum.reduce(%{}, fn event, acc ->
        actor_id = event["actor_id"]
        delta = event["delta"]

        Map.update(acc, actor_id, %{"total_xp" => delta, "event_count" => 1}, fn actor ->
          %{
            "total_xp" => actor["total_xp"] + delta,
            "event_count" => actor["event_count"] + 1
          }
        end)
      end)

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
      "actors" => per_actor,
      "event_count" => length(events),
      "reason_codes" => reason_codes
    }
  end

  defp validate_uuid(nil), do: {:error, "missing_uuid"}
  defp validate_uuid(val) when is_binary(val), do: :ok
  defp validate_uuid(_), do: {:error, "invalid_uuid"}

  defp validate_slug(nil), do: {:error, "missing_slug"}
  defp validate_slug(val) when is_binary(val), do: :ok
  defp validate_slug(_), do: {:error, "invalid_slug"}

  defp validate_string(nil), do: {:error, "missing_string"}
  defp validate_string(val) when is_binary(val), do: :ok
  defp validate_string(_), do: {:error, "invalid_string"}

  defp validate_integer(nil), do: {:error, "missing_integer"}
  defp validate_integer(val) when is_integer(val), do: :ok
  defp validate_integer(_), do: {:error, "invalid_integer"}

  defp validate_map(nil), do: {:error, "missing_map"}
  defp validate_map(val) when is_map(val), do: :ok
  defp validate_map(_), do: {:error, "invalid_map"}

  defp validate_inclusion(val, list) do
    if val in list, do: :ok, else: {:error, "invalid_value"}
  end
end
