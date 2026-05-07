defmodule BotArmyRpg.Handlers.GMHandler do
  @moduledoc """
  GM handler for turn management and action resolution.
  """

  require Logger

  alias BotArmyRpg.GM.{TurnManager, ActionResolver, BotPlayer, Narrator}

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

          bot_result = maybe_bot_autoplay(actor, updated, tenant_id, session_id)

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
            theme
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

  defp apply_resolution(tenant_id, session_id, character_id, action, resolution, session, theme) do
    # Apply stat updates
    if resolution["stat_updates"] != %{} do
      {:ok, character} = character_store().get(tenant_id, character_id)
      new_stats = Map.merge(character["stats"] || %{}, resolution["stat_updates"])
      character_store().update(tenant_id, character_id, %{"stats" => new_stats})
    end

    # Record turn
    turn_meta =
      TurnManager.record_turn(session, character_id, action, resolution["outcome"])

    # Clear pending action
    metadata = session["metadata"] || %{}
    cleaned_metadata = Map.drop(metadata, ["pending_action"])
    merged_metadata = Map.merge(cleaned_metadata, turn_meta)

    session_store().update(tenant_id, session_id, %{"metadata" => merged_metadata})

    # Generate narration
    {:ok, narration} = Narrator.narrate_action(action, resolution, theme)

    # Add scene fact
    scene_fact_store().append(%{
      "session_id" => session_id,
      "tenant_id" => tenant_id,
      "fact" =>
        "#{get_actor_name(character_id, tenant_id)} #{action["action_type"]}ed: #{resolution["outcome"]}"
    })

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
       "narration" => narration
     }}
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

  defp get_actor_name(character_id, tenant_id) do
    case character_store().get(tenant_id, character_id) do
      {:ok, character} -> character["name"] || "Unknown"
      _ -> "Unknown"
    end
  end

  defp resolve_tenant_id(params, message) do
    params["tenant_id"] || message["tenant_id"] || BotArmyRuntime.Tenant.default_tenant_id()
  end

  defp require_session_active(%{"status" => "active"}), do: :ok
  defp require_session_active(_), do: {:error, :session_not_active}
end
