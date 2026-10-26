defmodule BotArmyRpg.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the RPG bot.

  Subscribes to rpg.* subjects and routes messages to handlers.
  """

  use GenServer
  require Logger

  alias BotArmyLibraryRuntime.NATS.{Connection, Reply}
  alias BotArmyLibraryRuntime.Registry, as: BotArmyRegistry
  alias BotArmyLibraryCore.NATS.Decoder

  alias BotArmyRpg.Handlers.{
    CampaignHandler,
    CharacterHandler,
    GMHandler,
    IdentityHandler,
    LootHandler,
    LoreHandler,
    PartyHandler,
    QuestHandler,
    RollHandler,
    SceneFactHandler,
    SessionContextHandler,
    SessionHandler,
    ThemeHandler,
    WorldSnapshotHandler
  }

  @registry_heartbeat_ms 20_000
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
      subject: "rpg.session.open",
      type: :request_reply,
      description: "Enter the open window, opening one if there is none"
    },
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
      description: "Gather narrative context for a user session, including its party"
    },
    # The party routes, registered 2026-09-29. `BotArmyRpg.Handlers.PartyHandler` had
    # answered these four subjects since it was written, and nothing subscribed to any
    # of them, so every party call was dropped by core NATS while the code sat in the
    # tree looking finished.
    #
    # `rpg.party.auto_populate` is left out on purpose: its list of bot ids is a
    # hardcoded guess (`gtd`, `llm`) that does not match the characters the fleet
    # actually has (`gtd_bot`, `llm_bot`), so registering it today would recruit a
    # parallel ghost of every companion. Register it once that list comes from the
    # runtime registry.
    %{
      subject: "rpg.party.get",
      type: :request_reply,
      description: "Get an identity's party and companion roster"
    },
    %{
      subject: "rpg.party.add",
      type: :request_reply,
      description: "Recruit a bot companion into the party"
    },
    %{
      subject: "rpg.party.remove",
      type: :request_reply,
      description: "Take a companion out of the party"
    },
    # Added 0.15.48 with `BotArmyRpg.PartyStore.set_narrator/3`: the narrator is a role a
    # member holds (at most one), not a turn, and this is how it is named.
    %{
      subject: "rpg.party.set_narrator",
      type: :request_reply,
      description: "Name one member the party's narrator (null clears it)"
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
      description: "Generate GM narration for a scene (async: true answers at once)"
    },
    %{
      subject: "rpg.scene.narration.get",
      type: :request_reply,
      description: "Read back the last scene narration the GM wrote for a table"
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

  @doc """
  Every subject this consumer subscribes to.

  Public so that registration is testable: a handler with no subscriber is a route
  that silently drops its callers, and "somebody is listening" is not something a
  reader can check by looking at the handler.
  """
  def subjects, do: @subjects

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[RPG Consumer] Starting")

    {:ok, %{opts: opts}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    # Declared once and handed to the Connection, which holds this exact list and
    # re-subscribes it on every link it starts. Two things come from doing it this
    # way rather than per-subject `Gnat.sub/3` on each `{:nats, :connected}`:
    #
    #   1. A flapping broker cannot leave the bot dark — the registration survives
    #      the Gnat process, so the replacement link carries the subjects.
    #   2. A flapping broker cannot *multiply* the subscriptions. `Registry.register/3`
    #      replaces a pid's value instead of appending, so no matter how many times
    #      this runs, one subject means one subscription.
    #
    # The old shape did neither. Measured live 2026-10-13: the air<->mini leaf had
    # flapped 8 times and `rpg.character.create` had **112** subscriptions on it, so
    # a single request ran the handler twice and minted two characters (one of them
    # hers). One request must cost one write.
    :ok = Connection.subscribe(subscription_topics())

    Logger.info("[RPG Consumer] Subscribing to #{length(@subjects)} subjects")

    BotArmyRegistry.register("rpg", @subjects, @version)
    Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)

    {:noreply, state}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyLibraryRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers), fn ->
      Logger.debug("[RPG Consumer] Received message on #{msg.topic}")

      if msg.reply_to do
        handle_request_reply(msg)
      else
        case Decoder.decode(msg.body) do
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
  def handle_info(:registry_heartbeat, state) do
    BotArmyRegistry.register("rpg", @subjects, @version)
    Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    {:noreply, state}
  end

  @doc """
  Resolves one request into `{:ok, data}` or `{:error, reason}`.

  Public because this is the seam every route passes through. A handler that raises, or
  one whose store is not running, must cost that single request an honest refusal — the
  alternative is the Consumer dying, which silences every other route until a restart.
  """
  def dispatch(topic, body) do
    route_request(topic, body)
  rescue
    exception ->
      log_refusal(topic, "raised", Exception.message(exception))
      {:error, :handler_crashed}
  catch
    :exit, reason ->
      log_refusal(topic, "exited", describe_exit(reason))
      {:error, :handler_crashed}
  end

  defp handle_request_reply(msg) do
    reply = encode_reply(dispatch(msg.topic, decode_request_body(msg.body)))

    # The answer goes out on the same link the request arrived on (`msg.gnat`). A
    # replaced connection can no longer send into a dead socket, and this module no
    # longer has to remember which link happened to be current.
    Connection.publish(msg.gnat, msg.reply_to, reply)
  end

  defp route_request(topic, body) do
    case topic do
      "rpg.identity.bind" ->
        IdentityHandler.handle_bind(body)

      "rpg.identity.resolve" ->
        IdentityHandler.handle_resolve(body)

      "rpg.character.create" ->
        CharacterHandler.handle_create(body)

      "rpg.character.get" ->
        CharacterHandler.handle_get(body)

      "rpg.character.get_by_bot" ->
        CharacterHandler.handle_get_by_bot(body)

      "rpg.character.update" ->
        CharacterHandler.handle_update(body)

      "rpg.character.list" ->
        CharacterHandler.handle_list(body)

      "rpg.character.ensure" ->
        CharacterHandler.handle_ensure(body)

      "rpg.campaign.start" ->
        CampaignHandler.handle_start(body)

      "rpg.campaign.get" ->
        CampaignHandler.handle_get(body)

      "rpg.campaign.close" ->
        CampaignHandler.handle_close(body)

      "rpg.campaign.roster.get" ->
        CampaignHandler.handle_roster_get(body)

      "rpg.campaign.roster.update" ->
        CampaignHandler.handle_roster_update(body)

      "rpg.campaign.xp.add" ->
        CampaignHandler.handle_xp_add(body)

      "rpg.campaign.xp.ledger" ->
        CampaignHandler.handle_xp_ledger(body)

      "rpg.character.award_xp" ->
        CharacterHandler.handle_award_xp(body)

      "rpg.character.equip" ->
        CharacterHandler.handle_equip(body)

      "rpg.character.unequip" ->
        CharacterHandler.handle_unequip(body)

      "rpg.loot.generate" ->
        LootHandler.handle_generate(body)

      "rpg.roll.dice" ->
        RollHandler.handle_roll(body)

      "rpg.session.start" ->
        SessionHandler.handle_start(body)

      "rpg.session.open" ->
        SessionHandler.handle_open(body)

      "rpg.session.resume" ->
        SessionHandler.handle_resume(body)

      "rpg.session.join" ->
        SessionHandler.handle_join(body)

      "rpg.session.leave" ->
        SessionHandler.handle_leave(body)

      "rpg.party.get" ->
        PartyHandler.handle_get(body)

      "rpg.party.add" ->
        PartyHandler.handle_add(body)

      "rpg.party.remove" ->
        PartyHandler.handle_remove(body)

      "rpg.party.set_narrator" ->
        PartyHandler.handle_set_narrator(body)

      "rpg.session.pause" ->
        SessionHandler.handle_pause(body)

      "rpg.session.end" ->
        SessionHandler.handle_end(body)

      "rpg.session.describe" ->
        SessionHandler.handle_describe(body)

      "rpg.session.state" ->
        SessionHandler.handle_state(body)

      "rpg.session.list" ->
        SessionHandler.handle_list(body)

      "rpg.session.gather_context" ->
        SessionContextHandler.handle_gather_context(body)

      "rpg.adventure.context.query" ->
        SessionContextHandler.handle_adventure_context(body)

      "rpg.scene.fact.add" ->
        SceneFactHandler.handle_add(body)

      "rpg.scene.fact.list" ->
        SceneFactHandler.handle_list(body)

      "rpg.theme.get" ->
        ThemeHandler.handle_get(body)

      "rpg.theme.change" ->
        ThemeHandler.handle_change(body)

      "rpg.theme.list" ->
        ThemeHandler.handle_list(body)

      "rpg.theme.presets.list" ->
        ThemeHandler.handle_presets_list(body)

      "rpg.lore.snapshot" ->
        LoreHandler.handle_snapshot(body)

      "rpg.lore.ingest" ->
        LoreHandler.handle_ingest(body)

      "rpg.world.snapshot" ->
        WorldSnapshotHandler.handle_snapshot(body)

      "rpg.turn.start_round" ->
        GMHandler.handle_turn_start_round(body)

      "rpg.turn.next" ->
        GMHandler.handle_turn_next(body)

      "rpg.turn.whose" ->
        GMHandler.handle_turn_whose(body)

      "rpg.action.declare" ->
        GMHandler.handle_action_declare(body)

      "rpg.action.resolve" ->
        GMHandler.handle_action_resolve(body)

      "rpg.scene.narrate" ->
        GMHandler.handle_scene_narrate(body)

      "rpg.scene.narration.get" ->
        GMHandler.handle_scene_narration_get(body)

      "rpg.quest.create" ->
        QuestHandler.handle_create(body)

      "rpg.quest.list" ->
        QuestHandler.handle_list(body)

      "rpg.quest.complete" ->
        QuestHandler.handle_complete(body)

      _ ->
        {:error, :unknown_subject}
    end
  end

  defp encode_reply({:ok, data}), do: Reply.ok(data)
  defp encode_reply({:error, reason}), do: Reply.error(inspect(reason), :request_failed)

  # Never `inspect/1` a call's reason wholesale: `{:noproc, {GenServer, :call, [mod, fun,
  # args]}}` embeds the arguments, so this keeps the shape and drops them.
  defp describe_exit({reason, {mod, fun, _args}}),
    do: "#{inspect(reason)} from #{inspect(mod)}.#{fun}"

  defp describe_exit(reason), do: inspect(reason, limit: 4)

  defp log_refusal(topic, how, detail) do
    Logger.error("[RPG Consumer] Handler #{how} on #{topic}; refusing this request: #{detail}")
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
