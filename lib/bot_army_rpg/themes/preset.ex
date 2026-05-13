defmodule BotArmyRpg.Themes.Preset do
  @moduledoc """
  Behaviour for curated RPG theme preset modules.

  A preset module returns a complete theme map (settings, vocabulary, NPC
  personas, scene templates, mechanic rules) keyed by a stable string name.
  Modules that `use BotArmyRpg.Themes.Preset` are auto-discovered by
  `BotArmyRpg.Themes.Registry.list/0`, so adding a new theme requires no
  edits to `ThemeHandler` or any other registration point.

  ## Required callbacks

    * `name/0` — stable lowercase id, e.g. `"iron_kingdoms"`.
    * `display_name/0` — human-readable label, e.g. `"Iron Kingdoms"`.
    * `description/0` — one or two sentences for theme pickers.
    * `theme/0` — full theme map shaped for
      `BotArmyRpg.ThemeStore.set_current/3`.

  ## Required theme keys

  The `theme/0` map must contain every key in
  `BotArmyRpg.Themes.Preset.required_keys/0`. `BotArmyRpg.Handlers.ThemeHandler`
  validates this before persisting and rejects incomplete presets.

  ## Example

      defmodule BotArmyRpg.Themes.MyTheme do
        use BotArmyRpg.Themes.Preset

        @impl true
        def name, do: "my_theme"

        @impl true
        def display_name, do: "My Theme"

        @impl true
        def description, do: "Short pitch."

        @impl true
        def theme do
          %{
            "setting" => "...",
            "tone" => "...",
            "mechanic" => "...",
            "vocabulary" => %{},
            "templates" => %{},
            "npc_personas" => %{},
            "rules" => %{}
          }
        end
      end
  """

  @callback name() :: String.t()
  @callback display_name() :: String.t()
  @callback description() :: String.t()
  @callback theme() :: map()

  @required_keys ~w(setting tone mechanic vocabulary templates npc_personas rules)

  @doc """
  Keys every theme map must contain (top-level).
  """
  def required_keys, do: @required_keys

  @doc """
  Returns the list of keys missing from a theme map, in declaration order.
  """
  def missing_keys(theme) when is_map(theme) do
    Enum.filter(@required_keys, fn key -> not Map.has_key?(theme, key) end)
  end

  def missing_keys(_), do: @required_keys

  defmacro __using__(_opts) do
    quote do
      @behaviour BotArmyRpg.Themes.Preset

      @doc false
      def __theme_preset__, do: true
    end
  end
end
