defmodule BotArmyRpg.Handlers.SessionContextHandler do
  @moduledoc """
  Handles `rpg.session.gather_context` — narrative context for other bots.

  Fetches the active RPG session, scene facts, character, and current theme
  so fitness.chat, synapse, or any other bot can flavor responses with
  Resistance Chronicle narrative state.
  """

  require Logger

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  defp theme_store do
    Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
  end

  @doc """
  Gather narrative context for a user/bot interaction.

  Expected payload:
    - "user_id" (string, required)
    - "bot_id" (string, optional — character of the speaking bot)
    - "session_id" (string, optional — if known)
    - "tenant_id" (string, optional)
    - "fact_limit" (integer, optional — max scene facts, default 10)

  Returns `{:ok, context_map}` or `{:error, reason}`.
  """
  def handle_gather_context(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = params["user_id"] || BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    bot_id = params["bot_id"]
    session_id = params["session_id"]
    fact_limit = Map.get(params, "fact_limit", 10)

    with {:ok, session} <- find_active_session(tenant_id, user_id, session_id),
         {:ok, facts} <- fetch_scene_facts(tenant_id, session["id"], fact_limit),
         {:ok, character} <- fetch_character(tenant_id, user_id, bot_id),
         {:ok, theme} <- fetch_theme(tenant_id) do
      context = %{
        "session_id" => session["id"],
        "session_status" => session["status"],
        "scene_description" => session["scene_description"],
        "session_metadata" => session["metadata"] || %{},
        "character" => character,
        "theme" => theme,
        "scene_facts" => Enum.map(facts, & &1["content"]),
        "tenant_id" => tenant_id,
        "user_id" => user_id
      }

      {:ok, context}
    end
  end

  # --- Private ---

  defp find_active_session(tenant_id, user_id, nil) do
    case session_store().list(tenant_id) do
      {:ok, sessions} ->
        active =
          Enum.filter(sessions, fn s ->
            s["user_id"] == user_id and s["status"] == "active"
          end)

        case active do
          [session | _] -> {:ok, session}
          [] -> {:error, :no_active_session}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_active_session(tenant_id, _user_id, session_id) do
    case session_store().get(tenant_id, session_id) do
      {:ok, session} ->
        if session["status"] == "active" do
          {:ok, session}
        else
          {:error, :session_not_active}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_scene_facts(tenant_id, session_id, limit) do
    case scene_fact_store().list_for_session(tenant_id, session_id) do
      {:ok, facts} ->
        recent =
          facts
          |> Enum.sort_by(& &1["created_at"], :desc)
          |> Enum.take(limit)

        {:ok, recent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_character(tenant_id, _user_id, nil) do
    # No bot_id provided — return minimal context
    {:ok, %{}}
  end

  defp fetch_character(tenant_id, _user_id, bot_id) do
    case character_store().get_by_bot_id(tenant_id, bot_id) do
      {:ok, char} -> {:ok, char}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_theme(tenant_id) do
    case theme_store().get_current(tenant_id) do
      {:ok, theme} -> {:ok, theme}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end
end
