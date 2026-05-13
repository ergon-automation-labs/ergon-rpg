defmodule BotArmyRpg.Handlers.ThemeHandler do
  @moduledoc """
  NATS request handlers for theme operations.

  Handles `rpg.theme.get`, `rpg.theme.change`, `rpg.theme.list`, and
  `rpg.theme.presets.list`.

  ## Presets

  `handle_change/1` accepts a `"preset"` field as a shorthand for a curated
  theme map. Presets are auto-discovered from any module that
  `use BotArmyRpg.Themes.Preset` (see `BotArmyRpg.Themes.Registry`).
  Explicit fields in the same payload (`setting`, `tone`, `vocabulary`, …)
  override the preset, so a preset can be used as a base and tweaked.

  ## Validation

  Before persistence, the merged theme map is checked for the keys listed in
  `BotArmyRpg.Themes.Preset.required_keys/0`. Missing keys are returned as
  `{:error, {:invalid_theme, [missing_keys]}}` without touching the store.
  """
  require Logger

  alias BotArmyRpg.Themes.{Preset, Registry}

  @theme_fields Preset.required_keys()

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

    with {:ok, theme_data} <- resolve_theme_data(params),
         :ok <- validate_theme(theme_data) do
      case theme_store().set_current(tenant_id, theme_data, changed_by) do
        {:ok, theme} ->
          Logger.info("[ThemeHandler] Theme changed to #{theme["setting"]}/#{theme["tone"]}")
          {:ok, theme}

        {:error, reason} ->
          Logger.error("[ThemeHandler] Theme change failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("[ThemeHandler] Theme change rejected: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_list(message) do
    params = message["payload"] || message
    tenant_id = params["tenant_id"] || message["tenant_id"] || default_tenant_id()

    theme_store().list(tenant_id)
  end

  def handle_presets_list(_message) do
    presets =
      Registry.list()
      |> Enum.map(fn p ->
        %{
          "name" => p.name,
          "display_name" => p.display_name,
          "description" => p.description,
          "mechanic" => p.mechanic
        }
      end)

    {:ok, %{"presets" => presets}}
  end

  defp resolve_theme_data(%{"preset" => name} = params) when is_binary(name) do
    case Registry.fetch_theme(name) do
      {:ok, theme} ->
        overrides = Map.take(params, @theme_fields)
        {:ok, Map.merge(theme, overrides)}

      :error ->
        {:error, {:unknown_preset, name}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_theme_data(params) do
    {:ok, Map.take(params, @theme_fields)}
  end

  defp validate_theme(theme_data) do
    case Preset.missing_keys(theme_data) do
      [] -> :ok
      missing -> {:error, {:invalid_theme, missing}}
    end
  end
end
