defmodule BotArmyRpg.Handlers.SceneFactHandler do
  require Logger

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  def handle_add(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = Map.get(params, "user_id") || Map.get(message, "user_id")

    payload =
      Map.merge(params, %{
        "tenant_id" => tenant_id,
        "user_id" => user_id
      })

    case scene_fact_store().append(payload) do
      {:ok, fact} ->
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

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    scene_fact_store().list_for_session(tenant_id, session_id)
  end
end
