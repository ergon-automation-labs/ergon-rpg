defmodule Mix.Tasks.Rpg.Gen.Theme do
  @shortdoc "Scaffold a new RPG theme preset module + test"

  @moduledoc """
  Generates a new theme preset for `bot_army_rpg`.

  ## Usage

      mix rpg.gen.theme NAME=cyberpunk_red
      mix rpg.gen.theme NAME=cyberpunk_red DISPLAY="Cyberpunk Red" MECHANIC="d10 + stat + skill"

  ## Arguments

    * `NAME` — required. Snake_case identifier. Becomes both the module
      suffix (`BotArmyRpg.Themes.CyberpunkRed`) and the preset's `name/0`
      string returned by `BotArmyRpg.Themes.Preset`.
    * `DISPLAY` — optional. Human-readable label used by
      `display_name/0`. Defaults to a titlecased version of `NAME`.
    * `MECHANIC` — optional. Free-text description of the mechanical
      chassis. Defaults to `"TBD"`.

  ## What gets generated

    * `lib/bot_army_rpg/themes/<name>.ex` — preset module that
      `use BotArmyRpg.Themes.Preset`. Includes every required theme key
      with placeholder values so the module compiles and validates
      against `BotArmyRpg.Themes.Preset.required_keys/0` immediately.
    * `test/bot_army_rpg/themes/<name>_test.exs` — structural test that
      mirrors `iron_kingdoms_test.exs` and asserts the full theme shape.

  The generator refuses to overwrite existing files. Edit the placeholders
  by hand after running; the structural test stays green throughout.

  ## Auto-registration

  Because the generated module uses the `Preset` behaviour, it is picked up
  automatically by `BotArmyRpg.Themes.Registry.list/0` and surfaced via the
  `rpg.theme.presets.list` NATS subject. No edit to `ThemeHandler` is
  needed.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)

    name = opts[:name] || raise_missing!()
    validate_name!(name)

    display = opts[:display] || titlecase(name)
    mechanic = opts[:mechanic] || "TBD"
    module_suffix = camelcase(name)

    write!(module_path(name), module_template(name, display, mechanic, module_suffix))
    write!(test_path(name), test_template(name, display, module_suffix))

    Mix.shell().info("""

      Generated theme preset: #{module_suffix}
        lib/bot_army_rpg/themes/#{name}.ex
        test/bot_army_rpg/themes/#{name}_test.exs

      Next steps:
        mix compile
        mix test --no-start test/bot_army_rpg/themes/#{name}_test.exs
        # then fill in vocabulary, npc_personas, templates, rules
    """)
  end

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        ["NAME", v] -> Keyword.put(acc, :name, v)
        ["DISPLAY", v] -> Keyword.put(acc, :display, v)
        ["MECHANIC", v] -> Keyword.put(acc, :mechanic, v)
        _ -> acc
      end
    end)
  end

  defp raise_missing! do
    Mix.raise(
      "rpg.gen.theme requires NAME=<snake_case_name> (e.g. NAME=cyberpunk_red). " <>
        "See `mix help rpg.gen.theme` for full syntax."
    )
  end

  defp validate_name!(name) do
    unless name =~ ~r/^[a-z][a-z0-9_]*$/ do
      Mix.raise("Invalid NAME #{inspect(name)} — must be snake_case starting with a letter.")
    end
  end

  defp module_path(name), do: Path.join(["lib", "bot_army_rpg", "themes", "#{name}.ex"])

  defp test_path(name),
    do: Path.join(["test", "bot_army_rpg", "themes", "#{name}_test.exs"])

  defp write!(path, contents) do
    if File.exists?(path) do
      Mix.raise("Refusing to overwrite existing file: #{path}")
    end

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, contents)
    Mix.shell().info("  * created #{path}")
  end

  defp titlecase(name) do
    name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp camelcase(name) do
    name
    |> String.split("_")
    |> Enum.map_join("", &String.capitalize/1)
  end

  defp module_template(name, display, mechanic, suffix) do
    """
    defmodule BotArmyRpg.Themes.#{suffix} do
      @moduledoc \"\"\"
      #{display} theme preset.

      TODO: describe the setting, tone, and what flipping to this theme does
      to narration. Note any mechanical departures from the default d20
      chassis under `rules.resolution`.
      \"\"\"

      use BotArmyRpg.Themes.Preset

      @impl true
      def name, do: "#{name}"

      @impl true
      def display_name, do: "#{display}"

      @impl true
      def description do
        "TODO: short pitch shown in theme pickers."
      end

      @impl true
      def theme do
        %{
          "setting" => "#{display}",
          "tone" => "TODO: tone string for the narrator prompt",
          "mechanic" => "#{mechanic}",
          "vocabulary" => vocabulary(),
          "templates" => templates(),
          "npc_personas" => npc_personas(),
          "rules" => rules()
        }
      end

      defp vocabulary do
        # Substitute action verbs and setting nouns. The narrator weaves these
        # into LLM prompts and the fallback verb picker. Cover every action
        # type the bot can pick (attack, defend, buff, inspire, inspect,
        # negotiate, hack, evade, skill, move).
        %{
          "attack" => "TODO",
          "defend" => "TODO",
          "buff" => "TODO",
          "inspire" => "TODO",
          "inspect" => "TODO",
          "negotiate" => "TODO",
          "hack" => "TODO",
          "evade" => "TODO",
          "skill" => "TODO",
          "move" => "TODO"
        }
      end

      defp templates do
        %{
          "scene_intro" => "TODO: one-paragraph scene opener",
          "combat_intro" => "TODO: one-paragraph combat opener",
          "rest_scene" => "TODO: rest beat",
          "victory" => "TODO: victory beat",
          "defeat" => "TODO: defeat beat"
        }
      end

      defp npc_personas do
        # Each persona may declare `bot_assignments` to reskin specific bots
        # (resolved by `BotArmyRpg.Themes.Archetype`). Leave empty for purely
        # NPC personas.
        %{
          "example_persona" => %{
            "title" => "TODO Title",
            "demeanor" => "TODO demeanor",
            "carries" => [],
            "bot_assignments" => []
          }
        }
      end

      defp rules do
        # Leave `resolution` empty to inherit the d20 ±10 chassis, or declare
        # success_bands explicitly. See `BotArmyRpg.GM.RulesEngine` for the
        # supported band types.
        %{
          "action_types" => [
            "attack",
            "defend",
            "buff",
            "inspire",
            "inspect",
            "negotiate",
            "hack",
            "evade",
            "skill",
            "move"
          ]
        }
      end
    end
    """
  end

  defp test_template(name, display, suffix) do
    """
    defmodule BotArmyRpg.Themes.#{suffix}Test do
      use ExUnit.Case
      @moduletag :core

      alias BotArmyRpg.Themes.#{suffix}
      alias BotArmyRpg.Themes.Preset

      test "name/0 matches the generator argument" do
        assert #{suffix}.name() == "#{name}"
      end

      test "display_name/0 is human readable" do
        assert #{suffix}.display_name() == "#{display}"
      end

      test "theme/0 satisfies Preset.required_keys/0" do
        theme = #{suffix}.theme()
        assert Preset.missing_keys(theme) == [],
               "theme/0 is missing keys: \#{inspect(Preset.missing_keys(theme))}"
      end

      test "vocabulary covers every action type the bot can pick" do
        vocab = #{suffix}.theme()["vocabulary"]

        for action <- ~w(attack defend buff inspire inspect negotiate hack evade skill move) do
          assert Map.has_key?(vocab, action),
                 "vocabulary missing substitution for action \#{inspect(action)}"
        end
      end

      test "npc_personas entries carry the fields the narrator looks for" do
        for {key, persona} <- #{suffix}.theme()["npc_personas"] do
          assert is_binary(persona["title"]), "persona \#{key} missing title"
          assert is_binary(persona["demeanor"]), "persona \#{key} missing demeanor"
          assert is_list(persona["carries"]), "persona \#{key} missing carries"
        end
      end
    end
    """
  end
end
