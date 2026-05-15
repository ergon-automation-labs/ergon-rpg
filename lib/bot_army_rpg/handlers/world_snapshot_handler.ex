defmodule BotArmyRpg.Handlers.WorldSnapshotHandler do
  @moduledoc """
  NATS request handler for world snapshots.

  Responds to `rpg.world.snapshot` requests with Liberty City's current state:
  - Campaign theme snapshot (setting, tone, vocabulary, concerns)
  - System state (active bots, committed decisions, uptime)
  - Recent victories (completed tasks, achieved goals)
  - Bot agent details (what they fear, what they want remembered)

  Supports multi-tenant isolation via tenant_id and user_id.
  """

  require Logger

  defp theme_store do
    Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
  end

  defp default_tenant_id do
    Application.get_env(:bot_army_rpg, :default_tenant_id, "00000000-0000-0000-0000-000000000001")
  end

  @doc "Handle rpg.world.snapshot request"
  def handle_snapshot(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()
    user_id = params["user_id"] || message["user_id"] || "anonymous"

    with {:ok, theme} <- get_theme_snapshot(tenant_id) do
      world_snapshot = %{
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "campaign_theme" => theme,
        "system_metadata" => %{
          "note" =>
            "Bridge.world.snapshot facade enriches with active bots, recent victories, and agent details"
        }
      }

      Logger.info(
        "[WorldSnapshotHandler] Generated snapshot for tenant #{tenant_id}, user #{user_id}"
      )

      {:ok, world_snapshot}
    else
      error ->
        Logger.warning("[WorldSnapshotHandler] Failed to get theme snapshot: #{inspect(error)}")
        {:error, "theme_load_failed"}
    end
  end

  defp get_theme_snapshot(tenant_id) do
    case theme_store().get_current(tenant_id) do
      {:ok, theme} -> {:ok, theme}
      {:error, :not_found} -> {:ok, %{}}
      error -> error
    end
  end
end
