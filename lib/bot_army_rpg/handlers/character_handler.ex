defmodule BotArmyRpg.Handlers.CharacterHandler do
  require Logger

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_create(message) do
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

    case character_store().create(payload) do
      {:ok, character} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.character.created", character,
          tenant_id: tenant_id,
          user_id: user_id
        )

        {:ok, character}

      {:error, reason} ->
        Logger.error("[CharacterHandler] Create failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_get(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    character_id = params["character_id"]

    character_store().get(tenant_id, character_id)
  end

  def handle_update(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    character_id = params["character_id"]

    case character_store().update(tenant_id, character_id, params) do
      {:ok, character} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.character.updated", character,
          tenant_id: tenant_id
        )

        {:ok, character}

      {:error, reason} ->
        Logger.error("[CharacterHandler] Update failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    character_store().list(tenant_id)
  end
end
