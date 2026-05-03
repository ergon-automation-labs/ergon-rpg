defmodule BotArmyRpg.Handlers.ThemeHandler do
  @moduledoc """
  NATS request handlers for theme operations.

  Handles rpg.theme.get and rpg.theme.change.
  """
  require Logger

  defp theme_store do
    Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
  end

  defp default_tenant_id do
    Application.get_env(:bot_army_rpg, :default_tenant_id, "00000000-0000-0000-0000-000000000001")
  end

  def handle_get(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()

    theme_store().get_current(tenant_id)
  end

  def handle_change(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()
    changed_by = Map.get(params, "changed_by", "system")

    if changed_by not in ["player", "commander", "system"] do
      Logger.warning("[ThemeHandler] Theme change by non-standard actor: #{changed_by}")
    end

    theme_data =
      Map.take(params, ["setting", "tone", "mechanic", "vocabulary", "templates", "npc_personas"])

    case theme_store().set_current(tenant_id, theme_data, changed_by) do
      {:ok, theme} ->
        Logger.info("[ThemeHandler] Theme changed to #{theme["setting"]}/#{theme["tone"]}")
        {:ok, theme}

      {:error, reason} ->
        Logger.error("[ThemeHandler] Theme change failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
