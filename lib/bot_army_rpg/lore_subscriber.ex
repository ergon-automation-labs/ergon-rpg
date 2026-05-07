defmodule BotArmyRpg.LoreSubscriber do
  @moduledoc """
  Passive NATS fan-in for the Lore Keeper.

  Subscribes to allowlisted subjects (gossip, polls) and auto-ingests
  normalized lore facets so the world_snapshot reflects live operational
  reality.  Ephemeral — restart clears; truth layer remains canonical.
  """

  use GenServer
  require Logger

  alias BotArmyRpg.LoreKeeper

  @reconnect_delay_ms 5_000

  @subjects [
    "gossip.intent.proposed",
    "gossip.intent.resolved",
    "gossip.poll.broadcast",
    "gossip.poll.resolved",
    "gtd.poll.broadcast",
    "gtd.poll.resolved"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: [], conn: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("[LoreSubscriber] Connected to NATS, subscribing to allowlisted subjects")

        subscriptions =
          @subjects
          |> Enum.map(fn subject ->
            case Gnat.sub(conn, self(), subject) do
              {:ok, sub} ->
                Logger.info("[LoreSubscriber] Subscribed to #{subject}")
                sub

              {:error, reason} ->
                Logger.error(
                  "[LoreSubscriber] Failed to subscribe to #{subject}: #{inspect(reason)}"
                )

                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

      {:error, _reason} ->
        Logger.warning("[LoreSubscriber] NATS connection not ready, will retry")
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
    Logger.debug("[LoreSubscriber] Received on #{msg.topic}")

    with {:ok, decoded} <- BotArmyCore.NATS.Decoder.decode(msg.body),
         tenant_id <- Map.get(decoded, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id(),
         {:ok, payload} <- event_to_lore_payload(msg.topic, decoded) do
      case LoreKeeper.ingest(tenant_id, payload) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("[LoreSubscriber] Ingest failed: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        Logger.warning("[LoreSubscriber] Skipped #{msg.topic}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[LoreSubscriber] Disconnected from NATS, will reconnect")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: [], conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[LoreSubscriber] Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @doc false
  def event_to_lore_payload("gossip.intent.proposed", msg) do
    payload = Map.get(msg, "payload", %{})
    intent_key = Map.get(payload, "intent_key", "unknown")

    {:ok,
     %{
       "facets" => [
         %{
           "id" => "intent.#{intent_key}",
           "severity" => "info",
           "summary" => "Intent proposed: #{intent_key}",
           "ttl_seconds" => 3_600,
           "truth_refs" => [%{"kind" => "gossip", "ref" => msg["event_id"] || "unknown"}]
         }
       ]
     }}
  end

  def event_to_lore_payload("gossip.intent.resolved", msg) do
    payload = Map.get(msg, "payload", %{})
    intent_key = Map.get(payload, "intent_key", "unknown")

    {:ok,
     %{
       "facets" => [],
       "drops" => ["intent.#{intent_key}"]
     }}
  end

  def event_to_lore_payload("gossip.poll.broadcast", msg) do
    payload = Map.get(msg, "payload", %{})
    topic = Map.get(payload, "topic", "unknown")

    {:ok,
     %{
       "facets" => [
         %{
           "id" => "poll.#{topic}",
           "severity" => "info",
           "summary" => "Poll open: #{topic}",
           "ttl_seconds" => 86_400,
           "truth_refs" => [%{"kind" => "gossip", "ref" => msg["event_id"] || "unknown"}]
         }
       ]
     }}
  end

  def event_to_lore_payload("gossip.poll.resolved", msg) do
    payload = Map.get(msg, "payload", %{})
    topic = Map.get(payload, "topic", "unknown")

    {:ok,
     %{
       "facets" => [],
       "drops" => ["poll.#{topic}"]
     }}
  end

  def event_to_lore_payload("gtd.poll.broadcast", msg) do
    payload = Map.get(msg, "payload", %{})
    poll_id = Map.get(payload, "poll_id", "unknown")

    {:ok,
     %{
       "facets" => [
         %{
           "id" => "gtd_poll.#{poll_id}",
           "severity" => "info",
           "summary" => "GTD poll open: #{poll_id}",
           "ttl_seconds" => 86_400,
           "truth_refs" => [%{"kind" => "gtd_poll", "ref" => msg["event_id"] || "unknown"}]
         }
       ]
     }}
  end

  def event_to_lore_payload("gtd.poll.resolved", msg) do
    payload = Map.get(msg, "payload", %{})
    poll_id = Map.get(payload, "poll_id", "unknown")

    {:ok,
     %{
       "facets" => [],
       "drops" => ["gtd_poll.#{poll_id}"]
     }}
  end

  def event_to_lore_payload(topic, _msg) do
    {:error, {:unrecognized_topic, topic}}
  end
end
