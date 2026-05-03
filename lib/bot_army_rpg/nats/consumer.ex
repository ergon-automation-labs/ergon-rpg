defmodule BotArmyRpg.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the RPG bot.

  Subscribes to rpg.* subjects and routes messages to handlers.
  """

  use GenServer
  require Logger

  @reconnect_delay_ms 5000
  @version Mix.Project.config()[:version]

  @subjects [
    %{
      subject: "rpg.identity.bind",
      type: :request_reply,
      description: "Bind caller context to a user identity"
    },
    %{
      subject: "rpg.identity.resolve",
      type: :request_reply,
      description: "Resolve caller context to bound identity"
    },
    %{subject: "rpg.character.create", type: :request_reply, description: "Create a character"},
    %{subject: "rpg.character.get", type: :request_reply, description: "Get a character by ID"},
    %{subject: "rpg.character.update", type: :request_reply, description: "Update a character"},
    %{
      subject: "rpg.character.list",
      type: :request_reply,
      description: "List characters for tenant"
    },
    %{
      subject: "rpg.roll.dice",
      type: :request_reply,
      description: "Roll dice using standard notation"
    },
    %{subject: "rpg.session.start", type: :request_reply, description: "Start a new RPG session"},
    %{subject: "rpg.session.pause", type: :request_reply, description: "Pause an active session"},
    %{subject: "rpg.session.end", type: :request_reply, description: "End a session"},
    %{
      subject: "rpg.session.describe",
      type: :request_reply,
      description: "Set scene description"
    },
    %{subject: "rpg.session.state", type: :request_reply, description: "Get session state"},
    %{subject: "rpg.scene.fact.add", type: :request_reply, description: "Append a scene fact"},
    %{
      subject: "rpg.scene.fact.list",
      type: :request_reply,
      description: "List scene facts for session"
    },
    %{
      subject: "rpg.theme.get",
      type: :request_reply,
      description: "Get the current active theme"
    },
    %{
      subject: "rpg.theme.change",
      type: :request_reply,
      description: "Request a theme change"
    }
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[RPG Consumer] Starting")

    state = %{
      subscriptions: [],
      conn: nil,
      opts: opts
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("[RPG Consumer] Connected to NATS, subscribing to topics")

        subscriptions =
          subscription_topics()
          |> Enum.map(fn subject ->
            case Gnat.sub(conn, self(), subject) do
              {:ok, sub} ->
                Logger.info("[RPG Consumer] Subscribed to #{subject}")
                sub

              {:error, reason} ->
                Logger.error(
                  "[RPG Consumer] Failed to subscribe to #{subject}: #{inspect(reason)}"
                )

                nil
            end
          end)
          |> Enum.filter(&(not is_nil(&1)))

        BotArmyRuntime.Registry.register("rpg", @subjects, @version)

        {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

      {:error, _reason} ->
        Logger.warning("[RPG Consumer] NATS connection not ready, will retry")
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
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers), fn ->
      Logger.debug("[RPG Consumer] Received message on #{msg.topic}")

      if msg.reply_to do
        handle_request_reply(msg, state)
      else
        case BotArmyCore.NATS.Decoder.decode(msg.body) do
          {:ok, decoded_message} ->
            route_message(decoded_message, msg.topic)

          {:error, reason} ->
            Logger.warning(
              "[RPG Consumer] Failed to decode message from #{msg.topic}: #{inspect(reason)}"
            )
        end
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[RPG Consumer] Disconnected from NATS, will reconnect")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: [], conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[RPG Consumer] Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    BotArmyRuntime.Registry.register("rpg", @subjects, @version)
    {:noreply, state}
  end

  defp handle_request_reply(msg, state) do
    body = msg.body

    result =
      case msg.topic do
        "rpg.identity.bind" -> BotArmyRpg.Handlers.IdentityHandler.handle_bind(body)
        "rpg.identity.resolve" -> BotArmyRpg.Handlers.IdentityHandler.handle_resolve(body)
        "rpg.character.create" -> BotArmyRpg.Handlers.CharacterHandler.handle_create(body)
        "rpg.character.get" -> BotArmyRpg.Handlers.CharacterHandler.handle_get(body)
        "rpg.character.update" -> BotArmyRpg.Handlers.CharacterHandler.handle_update(body)
        "rpg.character.list" -> BotArmyRpg.Handlers.CharacterHandler.handle_list(body)
        "rpg.roll.dice" -> BotArmyRpg.Handlers.RollHandler.handle_roll(body)
        "rpg.session.start" -> BotArmyRpg.Handlers.SessionHandler.handle_start(body)
        "rpg.session.pause" -> BotArmyRpg.Handlers.SessionHandler.handle_pause(body)
        "rpg.session.end" -> BotArmyRpg.Handlers.SessionHandler.handle_end(body)
        "rpg.session.describe" -> BotArmyRpg.Handlers.SessionHandler.handle_describe(body)
        "rpg.session.state" -> BotArmyRpg.Handlers.SessionHandler.handle_state(body)
        "rpg.scene.fact.add" -> BotArmyRpg.Handlers.SceneFactHandler.handle_add(body)
        "rpg.scene.fact.list" -> BotArmyRpg.Handlers.SceneFactHandler.handle_list(body)
        "rpg.theme.get" -> BotArmyRpg.Handlers.ThemeHandler.handle_get(body)
        "rpg.theme.change" -> BotArmyRpg.Handlers.ThemeHandler.handle_change(body)
        _ -> {:error, :unknown_subject}
      end

    reply =
      case result do
        {:ok, data} -> BotArmyRuntime.NATS.Reply.ok(data)
        {:error, reason} -> BotArmyRuntime.NATS.Reply.error(inspect(reason), :request_failed)
      end

    if state.conn do
      Gnat.pub(state.conn, msg.reply_to, reply)
    end
  end

  defp route_message(_message, topic) do
    Logger.debug("[RPG Consumer] Routing pub/sub message from #{topic}")
  end

  defp subscription_topics do
    Enum.map(@subjects, & &1.subject)
  end
end
