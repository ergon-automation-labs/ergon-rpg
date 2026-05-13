defmodule BotArmyRpg.Themes.IronKingdomsTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.Themes.IronKingdoms

  test "theme/0 returns a map shaped for ThemeStore.set_current/3" do
    theme = IronKingdoms.theme()

    for key <- ~w(setting tone mechanic vocabulary templates npc_personas rules) do
      assert Map.has_key?(theme, key), "missing required key #{inspect(key)}"
    end

    assert is_binary(theme["setting"])
    assert is_binary(theme["tone"])
    assert is_binary(theme["mechanic"])
    assert is_map(theme["vocabulary"])
    assert is_map(theme["templates"])
    assert is_map(theme["npc_personas"])
    assert is_map(theme["rules"])
  end

  test "vocabulary covers every action type the bot can pick" do
    vocab = IronKingdoms.theme()["vocabulary"]

    for action <- ~w(attack defend buff inspire inspect negotiate hack evade skill move) do
      assert Map.has_key?(vocab, action),
             "vocabulary missing substitution for action #{inspect(action)}"

      assert is_binary(vocab[action])
    end
  end

  test "npc_personas entries carry the fields the narrator looks for" do
    for {key, persona} <- IronKingdoms.theme()["npc_personas"] do
      assert is_binary(persona["title"]), "persona #{key} missing title"
      assert is_binary(persona["demeanor"]), "persona #{key} missing demeanor"
      assert is_list(persona["carries"]), "persona #{key} missing carries"
    end
  end

  test "rules action_types list is non-empty and contains attack" do
    rules = IronKingdoms.theme()["rules"]

    assert is_list(rules["action_types"])
    assert "attack" in rules["action_types"]
  end
end
