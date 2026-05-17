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
    %{
      subject: "rpg.character.get_by_bot",
      type: :request_reply,
      description: "Get a character by bot_id"
    },
    %{subject: "rpg.character.update", type: :request_reply, description: "Update a character"},
    %{
      subject: "rpg.character.list",
      type: :request_reply,
      description: "List characters for tenant"
    },
    %{
      subject: "rpg.character.ensure",
      type: :request_reply,
      description: "Ensure bot character exists"
    },
    %{
      subject: "rpg.campaign.start",
      type: :request_reply,
      description: "Start a new campaign linked to a GTD project"
    },
    %{
      subject: "rpg.campaign.get",
      type: :request_reply,
      description: "Get campaign by project ID or campaign ID"
    },
    %{
      subject: "rpg.campaign.close",
      type: :request_reply,
      description: "Close a campaign and generate scorecard"
    },
    %{
      subject: "rpg.campaign.roster.get",
      type: :request_reply,
      description: "Get NPC roster for a campaign"
    },
    %{
      subject: "rpg.campaign.roster.update",
      type: :request_reply,
      description: "Add or update NPC roster entry"
    },
    %{
      subject: "rpg.campaign.xp.add",
      type: :request_reply,
      description: "Add XP event to campaign ledger"
    },
    %{
      subject: "rpg.campaign.xp.ledger",
      type: :request_reply,
      description: "Query XP ledger with optional filtering"
    },
    %{
      subject: "rpg.character.award_xp",
      type: :request_reply,
      description: "Award XP to a character and handle level-up"
    },
    %{
      subject: "rpg.character.equip",
      type: :request_reply,
      description: "Equip an item from inventory"
    },
    %{
      subject: "rpg.character.unequip",
      type: :request_reply,
      description: "Unequip an item from a slot"
    },
    %{
      subject: "rpg.loot.generate",
      type: :request_reply,
      description: "Generate random loot based on source and priority"
    },
    %{
      subject: "rpg.roll.dice",
      type: :request_reply,
      description: "Roll dice using standard notation"
    },
    %{subject: "rpg.session.start", type: :request_reply, description: "Start a new RPG session"},
    %{
      subject: "rpg.session.resume",
      type: :request_reply,
      description: "Resume a paused RPG session"
    },
    %{
      subject: "rpg.session.join",
      type: :request_reply,
      description: "Join a session as a character (owner must match resolved user)"
    },
    %{
      subject: "rpg.session.leave",
      type: :request_reply,
      description: "Leave a session for a character (must match prior join)"
    },
    %{subject: "rpg.session.pause", type: :request_reply, description: "Pause an active session"},
    %{subject: "rpg.session.end", type: :request_reply, description: "End a session"},
    %{
      subject: "rpg.session.describe",
      type: :request_reply,
      description: "Set scene description"
    },
    %{subject: "rpg.session.state", type: :request_reply, description: "Get session state"},
    %{subject: "rpg.session.list", type: :request_reply, description: "List sessions for tenant"},
    %{
      subject: "rpg.session.gather_context",
      type: :request_reply,
      description: "Gather narrative context for a user session"
    },
    %{
      subject: "rpg.adventure.context.query",
      type: :request_reply,
      description: "Query adventure context for a specific bot by bot_id"
    },
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
    },
    %{
      subject: "rpg.theme.list",
      type: :request_reply,
      description: "List available themes"
    },
    %{
      subject: "rpg.theme.presets.list",
      type: :request_reply,
      description: "List registered theme presets (auto-discovered)"
    },
    %{
      subject: "rpg.lore.snapshot",
      type: :request_reply,
      description: "Lore Keeper world_snapshot (Resistance Chronicle rollup)"
    },
    %{
      subject: "rpg.lore.ingest",
      type: :request_reply,
      description: "Ingest lore signals (explicit facets or ops_deploy / system_health shorthand)"
    },
    %{
      subject: "rpg.world.snapshot",
      type: :request_reply,
      description: "Get world snapshot (theme + system state + recent victories) for tenant/user"
    },
    %{
      subject: "rpg.turn.start_round",
      type: :request_reply,
      description: "Initialize turn order from session characters"
    },
    %{
      subject: "rpg.turn.next",
      type: :request_reply,
      description: "Advance to next actor in turn order"
    },
    %{
      subject: "rpg.turn.whose",
      type: :request_reply,
      description: "Get current actor without mutating state"
    },
    %{
      subject: "rpg.action.declare",
      type: :request_reply,
      description: "Character declares an action intent"
    },
    %{
      subject: "rpg.action.resolve",
      type: :request_reply,
      description: "GM adjudicates a declared action"
    },
    %{
      subject: "rpg.scene.narrate",
      type: :request_reply,
      description: "Generate GM narration for a scene"
    },
    %{
      subject: "rpg.narrative.daily",
      type: :pub_sub,
      description: "Daily narrative update based on character progression"
    },
    %{
      subject: "rpg.quest.create",
      type: :request_reply,
      description: "Create a new quest from GTD task"
    },
    %{
      subject: "rpg.quest.list",
      type: :request_reply,
      description: "List active or all quests for character"
    },
    %{
      subject: "rpg.quest.complete",
      type: :request_reply,
      description: "Complete a quest and award XP multiplier"
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
    body = decode_request_body(msg.body)

    result =
      case msg.topic do
        "rpg.identity.bind" ->
          BotArmyRpg.Handlers.IdentityHandler.handle_bind(body)

        "rpg.identity.resolve" ->
          BotArmyRpg.Handlers.IdentityHandler.handle_resolve(body)

        "rpg.character.create" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_create(body)

        "rpg.character.get" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_get(body)

        "rpg.character.get_by_bot" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_get_by_bot(body)

        "rpg.character.update" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_update(body)

        "rpg.character.list" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_list(body)

        "rpg.character.ensure" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_ensure(body)

        "rpg.campaign.start" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_start(body)

        "rpg.campaign.get" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_get(body)

        "rpg.campaign.close" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_close(body)

        "rpg.campaign.roster.get" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_roster_get(body)

        "rpg.campaign.roster.update" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_roster_update(body)

        "rpg.campaign.xp.add" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_xp_add(body)

        "rpg.campaign.xp.ledger" ->
          BotArmyRpg.Handlers.CampaignHandler.handle_xp_ledger(body)

        "rpg.character.award_xp" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_award_xp(body)

        "rpg.character.equip" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_equip(body)

        "rpg.character.unequip" ->
          BotArmyRpg.Handlers.CharacterHandler.handle_unequip(body)

        "rpg.loot.generate" ->
          BotArmyRpg.Handlers.LootHandler.handle_generate(body)

        "rpg.roll.dice" ->
          BotArmyRpg.Handlers.RollHandler.handle_roll(body)

        "rpg.session.start" ->
          BotArmyRpg.Handlers.SessionHandler.handle_start(body)

        "rpg.session.resume" ->
          BotArmyRpg.Handlers.SessionHandler.handle_resume(body)

        "rpg.session.join" ->
          BotArmyRpg.Handlers.SessionHandler.handle_join(body)

        "rpg.session.leave" ->
          BotArmyRpg.Handlers.SessionHandler.handle_leave(body)

        "rpg.session.pause" ->
          BotArmyRpg.Handlers.SessionHandler.handle_pause(body)

        "rpg.session.end" ->
          BotArmyRpg.Handlers.SessionHandler.handle_end(body)

        "rpg.session.describe" ->
          BotArmyRpg.Handlers.SessionHandler.handle_describe(body)

        "rpg.session.state" ->
          BotArmyRpg.Handlers.SessionHandler.handle_state(body)

        "rpg.session.list" ->
          BotArmyRpg.Handlers.SessionHandler.handle_list(body)

        "rpg.session.gather_context" ->
          BotArmyRpg.Handlers.SessionContextHandler.handle_gather_context(body)

        "rpg.adventure.context.query" ->
          BotArmyRpg.Handlers.SessionContextHandler.handle_adventure_context(body)

        "rpg.scene.fact.add" ->
          BotArmyRpg.Handlers.SceneFactHandler.handle_add(body)

        "rpg.scene.fact.list" ->
          BotArmyRpg.Handlers.SceneFactHandler.handle_list(body)

        "rpg.theme.get" ->
          BotArmyRpg.Handlers.ThemeHandler.handle_get(body)

        "rpg.theme.change" ->
          BotArmyRpg.Handlers.ThemeHandler.handle_change(body)

        "rpg.theme.list" ->
          BotArmyRpg.Handlers.ThemeHandler.handle_list(body)

        "rpg.theme.presets.list" ->
          BotArmyRpg.Handlers.ThemeHandler.handle_presets_list(body)

        "rpg.lore.snapshot" ->
          BotArmyRpg.Handlers.LoreHandler.handle_snapshot(body)

        "rpg.lore.ingest" ->
          BotArmyRpg.Handlers.LoreHandler.handle_ingest(body)

        "rpg.world.snapshot" ->
          BotArmyRpg.Handlers.WorldSnapshotHandler.handle_snapshot(body)

        "rpg.turn.start_round" ->
          BotArmyRpg.Handlers.GMHandler.handle_turn_start_round(body)

        "rpg.turn.next" ->
          BotArmyRpg.Handlers.GMHandler.handle_turn_next(body)

        "rpg.turn.whose" ->
          BotArmyRpg.Handlers.GMHandler.handle_turn_whose(body)

        "rpg.action.declare" ->
          BotArmyRpg.Handlers.GMHandler.handle_action_declare(body)

        "rpg.action.resolve" ->
          BotArmyRpg.Handlers.GMHandler.handle_action_resolve(body)

        "rpg.scene.narrate" ->
          BotArmyRpg.Handlers.GMHandler.handle_scene_narrate(body)

        "rpg.quest.create" ->
          BotArmyRpg.Handlers.QuestHandler.handle_create(body)

        "rpg.quest.list" ->
          BotArmyRpg.Handlers.QuestHandler.handle_list(body)

        "rpg.quest.complete" ->
          BotArmyRpg.Handlers.QuestHandler.handle_complete(body)

        _ ->
          {:error, :unknown_subject}
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

  defp decode_request_body(bin) when is_binary(bin) do
    case Jason.decode(bin) do
      {:ok, %{} = m} -> m
      _ -> %{}
    end
  end

  defp decode_request_body(%{} = m), do: m
  defp decode_request_body(_), do: %{}

  defp route_message(_message, topic) do
    Logger.debug("[RPG Consumer] Routing pub/sub message from #{topic}")
  end

  defp subscription_topics do
    Enum.map(@subjects, & &1.subject)
  end
end
