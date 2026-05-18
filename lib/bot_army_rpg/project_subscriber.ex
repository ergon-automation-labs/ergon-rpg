defmodule BotArmyRpg.ProjectSubscriber do
  @moduledoc """
  Subscribes to GTD project creation events and auto-creates RPG campaigns.

  When a GTD project is created, a campaign is automatically spawned with
  the project ID as gtd_project_id. This links the project to the RPG campaign
  lifecycle (theme selection, NPC rosters, XP tracking).
  """

  use GenServer
  require Logger

  alias BotArmyRpg.{CampaignStore, ThemeStore}

  @reconnect_delay_ms 5_000
  @subjects ["events.gtd.project.created"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: [], conn: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    try do
      case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
        {:ok, conn} ->
          BotArmyRuntime.NATS.Connection.subscribe_to_status()

          Logger.info(
            "[ProjectSubscriber] Connected to NATS, subscribing to project creation events"
          )

          subscriptions =
            @subjects
            |> Enum.map(fn subject ->
              case Gnat.sub(conn, self(), subject) do
                {:ok, sub} ->
                  Logger.info("[ProjectSubscriber] Subscribed to #{subject}")
                  sub

                {:error, reason} ->
                  Logger.error(
                    "[ProjectSubscriber] Failed to subscribe to #{subject}: #{inspect(reason)}"
                  )

                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

        {:error, _reason} ->
          Logger.warning("[ProjectSubscriber] NATS connection not ready, will retry")
          Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
          {:noreply, state}
      end
    rescue
      e ->
        Logger.warning("[ProjectSubscriber] Connection attempt failed: #{inspect(e)}, will retry")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    Logger.debug("[ProjectSubscriber] Received on #{msg.topic}")

    case BotArmyCore.NATS.Decoder.decode(msg.body) do
      {:ok, decoded} ->
        tenant_id = Map.get(decoded, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id()
        handle_project_created(tenant_id, decoded)

      {:error, reason} ->
        Logger.debug("[ProjectSubscriber] Decode failed #{msg.topic}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[ProjectSubscriber] Disconnected from NATS, will reconnect")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: [], conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[ProjectSubscriber] Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_project_created(tenant_id, event) do
    try do
      project = Map.get(event, "project", %{})
      project_id = Map.get(project, "id")
      project_name = Map.get(project, "name")

      if project_id && project_name do
        case create_campaign(tenant_id, project_id) do
          {:ok, campaign} ->
            Logger.info(
              "[ProjectSubscriber] Campaign created for project_id=#{project_id}, campaign_id=#{campaign["id"]}"
            )

          {:error, reason} ->
            Logger.warning(
              "[ProjectSubscriber] Failed to create campaign for project_id=#{project_id}: #{inspect(reason)}"
            )
        end
      else
        Logger.debug("[ProjectSubscriber] Incomplete project data, skipping campaign creation")
      end
    rescue
      e ->
        Logger.error(
          "[ProjectSubscriber] Exception in handle_project_created: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )
    end
  end

  defp create_campaign(tenant_id, gtd_project_id) do
    theme = get_current_theme(tenant_id)

    attrs = %{
      "tenant_id" => tenant_id,
      "gtd_project_id" => gtd_project_id,
      "theme_snapshot" => theme || default_theme(),
      "started_at" => DateTime.utc_now()
    }

    CampaignStore.handle_insert(attrs)
  end

  defp get_current_theme(tenant_id) do
    case ThemeStore.handle_get_current(tenant_id) do
      nil -> nil
      theme -> theme
    end
  rescue
    _ -> nil
  end

  defp default_theme do
    %{
      "name" => "default",
      "setting" => "A new chapter begins",
      "tone" => "adventurous"
    }
  end
end
