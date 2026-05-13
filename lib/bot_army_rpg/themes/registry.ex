defmodule BotArmyRpg.Themes.Registry do
  @moduledoc """
  Discovery of theme preset modules.

  Lazily scans every module in the `:bot_army_rpg` application and surfaces
  the ones that `use BotArmyRpg.Themes.Preset` (identified by the
  `__theme_preset__/0` marker the behaviour injects).

  No GenServer, no compile-time table — relies on
  `Application.spec/2` + `Code.ensure_loaded?/1`, so adding a new theme
  module is the entire registration step.
  """

  alias BotArmyRpg.Themes.Preset

  @app :bot_army_rpg

  @doc """
  List all registered theme presets as descriptor maps.

  Each entry: `%{name, display_name, description, mechanic, module}`.
  """
  def list do
    scan_modules()
    |> Enum.map(&describe/1)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Fetch a preset by its `name/0`.

  Returns `{:ok, descriptor}` or `:error`.
  """
  def fetch(name) when is_binary(name) do
    case Enum.find(list(), fn p -> p.name == name end) do
      nil -> :error
      descriptor -> {:ok, descriptor}
    end
  end

  def fetch(_), do: :error

  @doc """
  Same as `fetch/1` but returns the resolved theme map directly.
  """
  def fetch_theme(name) do
    with {:ok, %{module: module}} <- fetch(name) do
      theme = module.theme()

      case Preset.missing_keys(theme) do
        [] -> {:ok, theme}
        missing -> {:error, {:invalid_theme, missing}}
      end
    end
  end

  defp scan_modules do
    case Application.spec(@app, :modules) do
      nil -> []
      modules -> Enum.filter(modules, &theme_preset?/1)
    end
  end

  defp theme_preset?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__theme_preset__, 0)
  rescue
    _ -> false
  end

  defp describe(module) do
    %{
      name: safe_call(module, :name, "unknown"),
      display_name: safe_call(module, :display_name, "Unknown"),
      description: safe_call(module, :description, ""),
      mechanic: get_in(module.theme(), ["mechanic"]) || "",
      module: module
    }
  end

  defp safe_call(module, fun, default) do
    apply(module, fun, [])
  rescue
    _ -> default
  end
end
