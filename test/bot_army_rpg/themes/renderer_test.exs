defmodule BotArmyRpg.Themes.RendererTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.Themes.{Preset, Renderer}

  describe "render/3" do
    setup do
      theme = %{
        "setting" => "Verdant Hollow",
        "tone" => "wary and folkloric",
        "mechanic" => "1d12 + Aspect vs Reckoning",
        "vocabulary" => %{
          "attack" => "swing",
          "defend" => "hold",
          "buff" => "bless",
          "inspire" => "call the chorus",
          "inspect" => "read the omen",
          "negotiate" => "barter",
          "hack" => "pick the seal",
          "evade" => "walk unseen",
          "skill" => "ply the trade",
          "move" => "stride"
        },
        "templates" => %{
          "scene_intro" => "Wet smell of peat smoke, lapwing too close to the door.",
          "combat_intro" => "Crows lift in a single shape.",
          "rest_scene" => "The hearth ticks.",
          "victory" => "A careful inventory.",
          "defeat" => "A long walk back."
        },
        "npc_personas" => %{
          "council_warden" => %{
            "title" => "Council Warden",
            "demeanor" => "quiet, kind, has the last word",
            "carries" => ["wax-sealed warrant", "oak baton"],
            "bot_assignments" => []
          },
          "hedgewitch" => %{
            "title" => "Hedgewitch",
            "demeanor" => "brisk, unimpressed by titles",
            "carries" => ["dried herbs", "glass-eye fetish", "chipped knife"],
            "bot_assignments" => []
          }
        },
        "rules" => %{
          "action_types" => ~w(attack defend buff inspire inspect negotiate hack evade skill move)
        }
      }

      {:ok, theme: theme}
    end

    test "produces a module that compiles", %{theme: theme} do
      source = Renderer.render("verdant_hollow", theme)

      # Module compiles cleanly
      [{module, _}] = Code.compile_string(source, "verdant_hollow_test.ex")

      assert module == BotArmyRpg.Themes.VerdantHollow

      try do
        assert module.name() == "verdant_hollow"
        assert is_binary(module.display_name())
        assert is_binary(module.description())

        rendered_theme = module.theme()
        assert Preset.missing_keys(rendered_theme) == []
        assert rendered_theme["setting"] == "Verdant Hollow"
        assert rendered_theme["vocabulary"]["attack"] == "swing"
        assert rendered_theme["npc_personas"]["council_warden"]["title"] == "Council Warden"
      after
        :code.purge(module)
        :code.delete(module)
      end
    end

    test "embeds source path in the moduledoc", %{theme: theme} do
      source =
        Renderer.render("verdant_hollow", theme,
          source: "/tmp/sample.pdf",
          warnings: ["vocabulary: 'move' was TODO"]
        )

      assert source =~ "Source: /tmp/sample.pdf"
      assert source =~ "Extractor warnings:"
      assert source =~ "vocabulary: 'move' was TODO"
    end

    test "escapes embedded quotes safely" do
      tricky = %{
        "setting" => ~s(A place "called" Trouble),
        "tone" => "dry",
        "mechanic" => "d10",
        "vocabulary" => %{},
        "templates" => %{},
        "npc_personas" => %{},
        "rules" => %{"action_types" => ["attack"]}
      }

      source = Renderer.render("trouble", tricky)

      [{module, _}] = Code.compile_string(source, "trouble_test.ex")

      try do
        assert module.theme()["setting"] == ~s(A place "called" Trouble)
      after
        :code.purge(module)
        :code.delete(module)
      end
    end

    test "renders an empty theme without crashing" do
      empty = %{
        "setting" => "Empty",
        "tone" => "blank",
        "mechanic" => "TBD",
        "vocabulary" => %{},
        "templates" => %{},
        "npc_personas" => %{},
        "rules" => %{}
      }

      source = Renderer.render("empty", empty)
      [{module, _}] = Code.compile_string(source, "empty_test.ex")

      try do
        rendered = module.theme()
        assert Preset.missing_keys(rendered) == []
        assert rendered["vocabulary"] == %{}
      after
        :code.purge(module)
        :code.delete(module)
      end
    end
  end
end
