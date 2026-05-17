defmodule BotArmyRpg.StaleCampaignCloser do
  @moduledoc """
  Periodically closes campaigns that have been inactive (no updates) for a threshold period.

  Schedules a recurring check every hour (configurable). For each active campaign,
  if `updated_at` is older than the stale threshold (default 30 days), calls
  `CampaignHandler.handle_close/1` to close it and generate a scorecard.

  The stale clock resets on any store write: XP grant, roster update, manual close attempt, etc.
  """

  use GenServer
  require Logger

  alias BotArmyRpg.{CampaignStore, Handlers.CampaignHandler}

  @default_check_interval_ms 3_600_000
  @default_stale_days 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    enabled = config(:stale_campaign_closer_enabled, true)
    state = %{enabled: enabled}

    if enabled do
      Logger.info("[StaleCampaignCloser] Starting (enabled)")
      {:ok, state, {:continue, :schedule}}
    else
      Logger.info("[StaleCampaignCloser] Starting (disabled)")
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_next_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_stale, state) do
    if state.enabled do
      check_and_close_stale()
    end

    schedule_next_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp check_and_close_stale do
    stale_days = config(:stale_campaign_stale_days, @default_stale_days)

    active_campaigns = CampaignStore.handle_list_active()

    Enum.each(active_campaigns, fn campaign ->
      campaign_id = campaign["id"]
      updated_at = campaign["updated_at"]

      case is_stale?(updated_at, stale_days) do
        true ->
          close_campaign(campaign_id)

        false ->
          :ok
      end
    end)
  end

  defp is_stale?(updated_at, stale_days) when is_nil(updated_at), do: false

  defp is_stale?(updated_at, stale_days) do
    days_elapsed = DateTime.diff(DateTime.utc_now(), updated_at, :day)
    days_elapsed >= stale_days
  end

  defp close_campaign(campaign_id) do
    case CampaignHandler.handle_close(%{"rpg_campaign_id" => campaign_id}) do
      {:ok, result} ->
        days = result["scorecard"]["date_range"] |> calc_days_active()

        Logger.info(
          "[StaleCampaignCloser] Closed stale campaign #{campaign_id} (inactive #{days} days)"
        )

      {:error, reason} ->
        Logger.warning(
          "[StaleCampaignCloser] Failed to close stale campaign #{campaign_id}: #{inspect(reason)}"
        )
    end
  end

  defp calc_days_active(%{"started_at" => started_at, "ended_at" => ended_at})
       when not is_nil(started_at) and not is_nil(ended_at) do
    DateTime.diff(ended_at, started_at, :day)
  end

  defp calc_days_active(_), do: 0

  defp schedule_next_check do
    interval_ms = config(:stale_campaign_check_interval_ms, @default_check_interval_ms)
    Process.send_after(self(), :check_stale, interval_ms)
  end

  defp config(key, default) do
    Application.get_env(:bot_army_rpg, key, default)
  end
end
