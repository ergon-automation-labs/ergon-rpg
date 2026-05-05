defmodule BotArmyRpg.Handlers.LoreHandler do
  @moduledoc """
  NATS handlers for `rpg.lore.snapshot` and `rpg.lore.ingest`.
  """
  defp default_tenant_id do
    Application.get_env(:bot_army_rpg, :default_tenant_id, "00000000-0000-0000-0000-000000000001")
  end

  def handle_snapshot(message) when is_map(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()

    case BotArmyRpg.LoreKeeper.snapshot(tenant_id) do
      {:ok, snap} ->
        {:ok, snap}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_snapshot(_), do: {:error, :invalid_message}

  def handle_ingest(message) when is_map(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()

    ingest_body = Map.drop(params, ["tenant_id"])

    case BotArmyRpg.LoreKeeper.ingest(tenant_id, ingest_body) do
      {:ok, meta} ->
        {:ok, Map.put(meta, "tenant_id", tenant_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_ingest(_), do: {:error, :invalid_message}
end
