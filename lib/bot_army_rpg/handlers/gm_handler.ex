defmodule BotArmyRpg.Handlers.GMHandler do
  @moduledoc """
  GM handler for turn management and action resolution.
  """

  require Logger

  alias BotArmyRpg.GM.{TurnManager, ActionResolver, BotPlayer, Narrator}
  alias BotArmyRpg.{PartyNarration, PartyRead, PartyStore}

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  defp theme_store do
    Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
  end

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  def handle_turn_start_round(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session) do
      turn_meta = TurnManager.build_turn_state(session)

      case session_store().update(tenant_id, session_id, %{"metadata" => turn_meta}) do
        {:ok, updated} ->
          actor = TurnManager.current_actor(updated)
          publish_turn_started(updated, actor, tenant_id)
          {:ok, %{"session" => updated, "current_actor" => actor}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def handle_turn_next(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session) do
      next_meta = TurnManager.advance_turn(session)

      case session_store().update(tenant_id, session_id, %{"metadata" => next_meta}) do
        {:ok, updated} ->
          actor = TurnManager.current_actor(updated)
          publish_turn_started(updated, actor, tenant_id)

          bot_result = maybe_enqueue_bot_autoplay(actor, updated, tenant_id, session_id)

          {:ok,
           %{
             "session" => updated,
             "current_actor" => actor,
             "round" => get_in(next_meta, ["turn_state", "round"]),
             "bot_action" => bot_result
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def handle_turn_whose(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id) do
      actor = TurnManager.current_actor(session)
      turn_state = get_in(session, ["metadata", "turn_state"]) || %{}

      {:ok,
       %{
         "current_actor" => actor,
         "round" => turn_state["round"],
         "active_index" => turn_state["active_index"],
         "turn_order" => turn_state["turn_order"]
       }}
    end
  end

  def handle_action_declare(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]
    character_id = params["character_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session),
         {:ok, _character} <- character_store().get(tenant_id, character_id) do
      action = %{
        "action_type" => params["action_type"],
        "target_id" => params["target_id"],
        "description" => params["description"]
      }

      metadata = session["metadata"] || %{}

      pending =
        Map.put(metadata, "pending_action", %{
          "character_id" => character_id,
          "action" => action
        })

      case session_store().update(tenant_id, session_id, %{"metadata" => pending}) do
        {:ok, _updated} ->
          {:ok,
           %{
             "session_id" => session_id,
             "character_id" => character_id,
             "action" => action,
             "status" => "declared"
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def handle_action_resolve(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]
    character_id = params["character_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session),
         {:ok, character} <- character_store().get(tenant_id, character_id),
         {:ok, theme} <- theme_store().get_current(tenant_id),
         {:ok, facts} <- scene_fact_store().list_for_session(tenant_id, session_id) do
      action =
        params["action"] ||
          get_in(session, ["metadata", "pending_action", "action"]) ||
          %{"action_type" => "attack"}

      case ActionResolver.resolve(action, character, theme, facts) do
        {:ok, resolution} ->
          apply_resolution(
            tenant_id,
            session_id,
            character_id,
            action,
            resolution,
            session,
            theme,
            character
          )

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def handle_scene_narrate(message) do
    params = message["payload"] || message
    tenant_id = resolve_tenant_id(params, message)
    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session),
         {:ok, theme} <- theme_store().get_current(tenant_id),
         {:ok, facts} <- scene_fact_store().list_for_session(tenant_id, session_id) do
      scene = params["scene_description"] || session["scene_description"]

      case Narrator.narrate_scene(scene, theme, facts) do
        {:ok, narration} ->
          BotArmyRpg.NATS.Publisher.publish(
            "rpg.scene.narrated",
            %{
              "session_id" => session_id,
              "scene_description" => scene,
              "narration" => narration
            },
            tenant_id: tenant_id
          )

          {:ok,
           %{
             "session_id" => session_id,
             "scene_description" => scene,
             "narration" => narration
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Private ---

  defp apply_resolution(
         tenant_id,
         session_id,
         character_id,
         action,
         resolution,
         session,
         theme,
         character
       ) do
    if resolution["stat_updates"] != %{} do
      {:ok, latest} = character_store().get(tenant_id, character_id)
      new_stats = Map.merge(latest["stats"] || %{}, resolution["stat_updates"])
      character_store().update(tenant_id, character_id, %{"stats" => new_stats})
    end

    turn_meta =
      TurnManager.record_turn(session, character_id, action, resolution["outcome"])

    metadata = session["metadata"] || %{}
    cleaned_metadata = Map.drop(metadata, ["pending_action"])
    merged_metadata = Map.merge(cleaned_metadata, turn_meta)

    session_store().update(tenant_id, session_id, %{"metadata" => merged_metadata})

    # Record outcome: action resolution success/failure
    try do
      outcome = Map.get(resolution, "outcome", "unknown")
      # Map RPG outcomes to OutcomeTracker's expected values
      outcome_result = if outcome in ["success", "critical"], do: "success", else: "failure"

      BotArmyLibraryLearning.OutcomeTracker.record(
        character_id,
        "rpg.action_resolution",
        "act",
        outcome_result,
        :rpg_outcome_tracker
      )
    rescue
      _ -> :ok
    end

    # Who narrates this turn. A party may hold one member in the `narrator` role, and
    # then the turn's words are hers: rpg asks her (`PartyNarration.ask/4`) and writes
    # none of them itself, so `narration` is nil here and her fact — signed with her
    # name — is the turn, if and when she writes it.
    #
    # With no narrator the GM narrates, as it always has: `GM.Narrator` asks the LLM as
    # "the Game Master narrating an action" and falls back to a template when the LLM is
    # away, and both are the theme's voice, so the fact is signed `"gm"`. The window
    # draws `source` as the speaker, so signing the acting character's `bot_id` would put
    # words in a bot's mouth that no bot said (that line was 0.15.49's fix). The actor is
    # not lost either way: the prompt and the fallback name her, and `turn_history`
    # records her turn.
    #
    # A party the read could not answer leaves the GM narrating (`unread_party/1`): a
    # store that is down must not take the table's words away.
    narrator = narrator_of(session, tenant_id)
    turn = %{"actor" => character, "action" => action, "resolution" => resolution}

    narration =
      case narrator do
        nil -> gm_turn(session_id, tenant_id, theme, turn)
        member -> ask_narrator(member, session, tenant_id, theme, turn)
      end

    # Publish event
    BotArmyRpg.NATS.Publisher.publish(
      "rpg.action.resolved",
      %{
        "session_id" => session_id,
        "character_id" => character_id,
        "action" => action,
        "resolution" => resolution,
        "narration" => narration
      },
      tenant_id: tenant_id
    )

    {:ok,
     %{
       "resolution" => resolution,
       "character_id" => character_id,
       "session_id" => session_id,
       "narration" => narration,
       "narrator" => narrator["bot_id"]
     }}
  end

  # The party's narrator, or nil. `PartyStore.narrator/1` is the only thing that decides
  # who narrates; this must not spell a second answer.
  defp narrator_of(session, tenant_id) do
    case PartyRead.read(tenant_id, session["user_id"]) do
      {:ok, party} -> PartyStore.narrator(party)
      {:error, reason} -> unread_party(reason)
    end
  rescue
    _ -> unread_party(:raised)
  catch
    :exit, _ -> unread_party(:down)
  end

  # A store that cannot answer is not a party with no narrator, but the turn still needs
  # its words: the GM narrates, and the failure is visible by its kind — never by the
  # arguments a dead call carries, which are the party's key (N+64).
  defp unread_party(reason) do
    Logger.warning("[GM] Party unread: #{inspect(PartyRead.shape(reason))}; the GM narrates")

    nil
  end

  # The GM narrates: it writes the fact the window reads as a turn, and hands the same
  # prose back to the caller. Scene facts are the only thing the window reads as a turn,
  # so prose merely published (`events.rpg.action.resolved`) never reaches the table.
  #
  # This replaced a mechanical line that was refused outright: the store reads
  # `"content"` and it was sent as a key named `"fact"`, and `content` is required, so
  # every bot turn was dropped in silence. The interpolation was not a fit turn either
  # — it conjugated action types by appending "ed" ("The Bard inspireed the party").
  defp gm_turn(session_id, tenant_id, theme, turn) do
    {:ok, narration} =
      Narrator.narrate_action(turn["action"], turn["resolution"], theme, turn["actor"])

    scene_fact_store().append(%{
      "session_id" => session_id,
      "tenant_id" => tenant_id,
      "content" => narration,
      "category" => "narration",
      "source" => "gm"
    })

    narration
  end

  # The narrator is a member: the words are hers, so the GM writes none of them. She is
  # asked once and never awaited — rpg cannot know whether she answers, so it reports the
  # turn as having no narration yet rather than inventing one.
  #
  # The ask is also written down, as a note on the window (`note_the_ask/3`): the window
  # reads its turns off the facts, so a turn that was handed to her and has no words yet
  # looks exactly like a turn nobody ever narrated. The note is what the window's pending
  # reading is built from (`SessionContextHandler`).
  #
  # A bus that will not take the ask is not a narrator who stayed silent: nothing reached
  # her, so the GM narrates, exactly as when the party cannot be read at all.
  defp ask_narrator(member, session, tenant_id, theme, turn) do
    case PartyNarration.ask(member, session, tenant_id, turn) do
      :ok ->
        note_the_ask(member, session, tenant_id)
        nil

      {:error, reason} ->
        Logger.warning(
          "[GM] Narration ask not published: #{inspect(PartyRead.shape(reason))}; the GM narrates"
        )

        gm_turn(session["id"], tenant_id, theme, turn)
    end
  end

  # The machinery speaking is not a person in the scene, so the note is signed `"system"`:
  # that is what keeps it out of the carry (`SceneFactStore.story?/1`) and out of the
  # window's turns, while `PartyNarration.asked?/1` still finds it in the facts. A note that
  # could not be written is reported by its kind and nothing else — the turn is not lost
  # because its bookkeeping failed.
  defp note_the_ask(member, session, tenant_id) do
    case scene_fact_store().append(%{
           "session_id" => session["id"],
           "tenant_id" => tenant_id,
           "content" => PartyNarration.note_content(member),
           "category" => PartyNarration.asked_category(),
           "source" => "system"
         }) do
      {:ok, _note} ->
        :ok

      {:error, reason} ->
        Logger.warning("[GM] The ask could not be noted: #{inspect(PartyRead.shape(reason))}")
    end
  end

  defp publish_turn_started(session, actor, tenant_id) do
    if actor do
      BotArmyRpg.NATS.Publisher.publish(
        "rpg.turn.your_turn",
        %{
          "session_id" => session["id"],
          "character_id" => actor["character_id"],
          "bot_id" => actor["bot_id"],
          "type" => actor["type"],
          "round" => get_in(session, ["metadata", "turn_state", "round"])
        },
        tenant_id: tenant_id
      )
    end
  end

  defp maybe_bot_autoplay(
         %{"type" => "bot", "character_id" => character_id, "bot_id" => bot_id},
         session,
         tenant_id,
         session_id
       ) do
    with {:ok, character} <- character_store().get(tenant_id, character_id),
         {:ok, theme} <- theme_store().get_current(tenant_id) do
      action = BotPlayer.decide_action(bot_id, character, session, theme)

      declare_payload = %{
        "session_id" => session_id,
        "tenant_id" => tenant_id,
        "character_id" => character_id,
        "action_type" => action["action_type"],
        "target_id" => action["target_id"],
        "description" => action["description"]
      }

      case handle_action_declare(declare_payload) do
        {:ok, _} ->
          resolve_payload = %{
            "session_id" => session_id,
            "tenant_id" => tenant_id,
            "character_id" => character_id
          }

          case handle_action_resolve(resolve_payload) do
            {:ok, resolution} ->
              Map.merge(action, %{
                "declared" => true,
                "resolved" => true,
                "resolution" => resolution
              })

            {:error, reason} ->
              Map.merge(action, %{
                "declared" => true,
                "resolved" => false,
                "error" => reason
              })
          end

        _ ->
          Map.put(action, "declared", false)
      end
    else
      _ ->
        nil
    end
  end

  defp maybe_bot_autoplay(_, _, _, _), do: nil

  defp maybe_enqueue_bot_autoplay(
         %{"type" => "bot", "character_id" => character_id, "bot_id" => bot_id} = actor,
         session,
         tenant_id,
         session_id
       ) do
    # Do not block rpg.turn.next request/reply on autoplay + narration.
    Task.start(fn ->
      _ = maybe_bot_autoplay(actor, session, tenant_id, session_id)
    end)

    %{
      "queued" => true,
      "resolved" => false,
      "character_id" => character_id,
      "bot_id" => bot_id
    }
  end

  defp maybe_enqueue_bot_autoplay(_, _, _, _), do: nil

  defp resolve_tenant_id(params, message) do
    params["tenant_id"] || message["tenant_id"] ||
      BotArmyLibraryRuntime.Tenant.default_tenant_id()
  end

  defp require_session_active(%{"status" => "active"}), do: :ok
  defp require_session_active(_), do: {:error, :session_not_active}
end
