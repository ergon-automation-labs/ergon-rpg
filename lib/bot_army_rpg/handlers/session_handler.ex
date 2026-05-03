defmodule BotArmyRpg.Handlers.SessionHandler do
  require Logger

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  def handle_start(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = Map.get(params, "user_id") || Map.get(message, "user_id")

    payload =
      Map.merge(params, %{
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "status" => "active"
      })

    case session_store().create(payload) do
      {:ok, session} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.session.started", session,
          tenant_id: tenant_id,
          user_id: user_id
        )

        {:ok, session}

      {:error, reason} ->
        Logger.error("[SessionHandler] Start failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_pause(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    case session_store().update(tenant_id, session_id, %{"status" => "paused"}) do
      {:ok, session} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.session.paused", session, tenant_id: tenant_id)
        {:ok, session}

      {:error, reason} ->
        Logger.error("[SessionHandler] Pause failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_end(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    case session_store().update(tenant_id, session_id, %{"status" => "ended"}) do
      {:ok, session} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.session.ended", session, tenant_id: tenant_id)
        {:ok, session}

      {:error, reason} ->
        Logger.error("[SessionHandler] End failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_describe(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]
    description = params["description"]

    session_store().update(tenant_id, session_id, %{"scene_description" => description})
  end

  def handle_state(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    session_store().get(tenant_id, session_id)
  end
end
