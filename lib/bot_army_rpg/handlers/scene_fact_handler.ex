defmodule BotArmyRpg.Handlers.SceneFactHandler do
  @moduledoc "Handles NATS messages for adding, listing, and clearing scene facts."
  require Logger

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  def handle_add(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = Map.get(params, "user_id") || Map.get(message, "user_id")

    payload =
      Map.merge(params, %{
        "tenant_id" => tenant_id,
        "user_id" => user_id
      })

    case scene_fact_store().append(payload) do
      {:ok, fact} ->
        touch_window(tenant_id, fact)

        BotArmyRpg.NATS.Publisher.publish("rpg.scene.fact.added", fact,
          tenant_id: tenant_id,
          user_id: user_id
        )

        {:ok, fact}

      {:error, reason} ->
        Logger.error("[SceneFactHandler] Add failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # A turn is the window being used, so the window's clock moves with it. This is what
  # makes "the newest window" mean *the conversation we were last in* rather than *the
  # last one created* — `BotArmyRpg.Sessions.active_for/2` reads that clock.
  #
  # Best effort on purpose: the turn is already stored and the caller is being told so,
  # and a clock that did not move reorders windows rather than losing anything. A
  # failure is logged rather than swallowed, because a silent one would look exactly
  # like a window that had simply not been used yet.
  defp touch_window(tenant_id, fact) do
    session_id = fact["session_id"] || fact["session"]

    with true <- is_binary(session_id),
         {:ok, _session} <- session_store().touch(tenant_id, session_id) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("[SceneFactHandler] Could not move the window's clock: #{inspect(reason)}")

      false ->
        Logger.warning("[SceneFactHandler] A stored turn names no window; the clock did not move")

      other ->
        Logger.warning("[SceneFactHandler] The clock did not move: #{inspect(other)}")
    end
  end

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    scene_fact_store().list_for_session(tenant_id, session_id)
  end
end
