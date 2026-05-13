defmodule BotArmyRpg.Themes.PresetTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.Themes.Preset

  describe "required_keys/0" do
    test "lists the seven top-level theme fields" do
      keys = Preset.required_keys()

      for required <- ~w(setting tone mechanic vocabulary templates npc_personas rules) do
        assert required in keys, "expected required_keys to include #{inspect(required)}"
      end

      assert length(keys) == 7
    end
  end

  describe "missing_keys/1" do
    test "returns [] when all keys present" do
      theme = %{
        "setting" => "x",
        "tone" => "x",
        "mechanic" => "x",
        "vocabulary" => %{},
        "templates" => %{},
        "npc_personas" => %{},
        "rules" => %{}
      }

      assert Preset.missing_keys(theme) == []
    end

    test "returns missing keys when fields are absent" do
      assert "vocabulary" in Preset.missing_keys(%{"setting" => "x"})
      assert "templates" in Preset.missing_keys(%{"setting" => "x"})
    end

    test "returns all keys when input is not a map" do
      assert Preset.missing_keys(nil) == Preset.required_keys()
      assert Preset.missing_keys("string") == Preset.required_keys()
    end
  end
end
