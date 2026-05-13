defmodule BotArmyRpg.Themes.ArchetypeTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.Themes.Archetype
  alias BotArmyRpg.Themes.IronKingdoms

  describe "for_bot/2 with Iron Kingdoms" do
    setup do
      %{theme: IronKingdoms.theme()}
    end

    test "returns the themed persona when the bot is assigned", %{theme: theme} do
      assert {:themed, persona} = Archetype.for_bot(theme, "gtd")
      assert persona["title"] == "Gobber Tinker"
      assert persona["_persona_key"] == "gobber_tinker"
      assert is_binary(persona["demeanor"])
    end

    test "matches synapse to the Iosan Envoy persona", %{theme: theme} do
      assert {:themed, persona} = Archetype.for_bot(theme, "synapse")
      assert persona["title"] == "Iosan Envoy"
    end

    test "strips the bot_army_ prefix on lookup", %{theme: theme} do
      assert {:themed, persona} = Archetype.for_bot(theme, "bot_army_sre")
      assert persona["title"] == "Trencher Sergeant"
    end

    test "matches each shared assignment (e.g. claude_bridge and llm both arcane mechanik)",
         %{theme: theme} do
      assert {:themed, %{"title" => "Arcane Mechanik"}} = Archetype.for_bot(theme, "llm")

      assert {:themed, %{"title" => "Arcane Mechanik"}} =
               Archetype.for_bot(theme, "claude_bridge")
    end

    test "falls back to Defaults for unmapped bots", %{theme: theme} do
      assert {:default, default} = Archetype.for_bot(theme, "some_unknown_bot")
      assert default["title"] == "Unknown Adventurer"
      assert default["class"] == "Adventurer"
    end
  end

  describe "for_bot/2 without a usable theme" do
    test "returns :no_theme when theme is nil" do
      assert :no_theme = Archetype.for_bot(nil, "gtd")
    end

    test "defaults when theme is an empty map" do
      assert {:default, default} = Archetype.for_bot(%{}, "gtd")
      assert default["title"] == "Human Scheduler"
    end
  end

  describe "for_character/2" do
    test "resolves via the character's bot_id" do
      theme = IronKingdoms.theme()

      assert {:themed, %{"title" => "Trencher Sergeant"}} =
               Archetype.for_character(theme, %{"bot_id" => "sre", "name" => "Sentinel"})
    end

    test "returns :no_actor when bot_id is missing or empty" do
      assert :no_actor = Archetype.for_character(IronKingdoms.theme(), %{"name" => "Player"})
      assert :no_actor = Archetype.for_character(IronKingdoms.theme(), %{"bot_id" => ""})
    end
  end

  describe "prompt_hint/1" do
    test "renders title and demeanor for themed personas" do
      hint =
        Archetype.prompt_hint(
          {:themed, %{"title" => "Gobber Tinker", "demeanor" => "fast-talking and shifty"}}
        )

      assert hint =~ "Gobber Tinker"
      assert hint =~ "fast-talking and shifty"
    end

    test "omits demeanor when blank" do
      hint = Archetype.prompt_hint({:themed, %{"title" => "Trencher", "demeanor" => ""}})
      assert hint =~ "Trencher"
      refute hint =~ "—"
    end

    test "renders default archetype titles" do
      hint = Archetype.prompt_hint({:default, %{"title" => "Human Scheduler"}})
      assert hint =~ "Human Scheduler"
    end

    test "returns an empty string for absent archetypes" do
      assert Archetype.prompt_hint(:no_theme) == ""
      assert Archetype.prompt_hint(:no_actor) == ""
    end
  end

  describe "display_label/2" do
    test "uses the themed title for themed archetypes" do
      assert Archetype.display_label({:themed, %{"title" => "Gobber Tinker"}}, "Gtd") ==
               "the Gobber Tinker"
    end

    test "prefers the given character name over the default title" do
      label = Archetype.display_label({:default, %{"title" => "Human Scheduler"}}, "Gtd")
      assert label == "Gtd"
    end

    test "falls back to a generic label when nothing is available" do
      assert Archetype.display_label(:no_theme) == "the character"
    end
  end
end
