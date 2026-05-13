defmodule BotArmyRpg.Themes.RegistryTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.Themes.Registry

  describe "list/0" do
    test "auto-discovers Iron Kingdoms via the Preset behaviour" do
      presets = Registry.list()
      names = Enum.map(presets, & &1.name)

      assert "iron_kingdoms" in names, "expected iron_kingdoms in #{inspect(names)}"
    end

    test "auto-discovers the Pathfinder preset alongside Iron Kingdoms" do
      names = Registry.list() |> Enum.map(& &1.name)

      assert "iron_kingdoms" in names
      assert "pathfinder" in names
    end

    test "returns descriptor maps with the expected fields" do
      [first | _] = Registry.list()

      for field <- [:name, :display_name, :description, :mechanic, :module] do
        assert Map.has_key?(first, field), "missing #{inspect(field)} in #{inspect(first)}"
      end
    end

    test "sorts presets by name" do
      names = Registry.list() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "fetch/1" do
    test "returns {:ok, descriptor} for known presets" do
      assert {:ok, %{name: "iron_kingdoms", display_name: "Iron Kingdoms"}} =
               Registry.fetch("iron_kingdoms")
    end

    test "returns :error for unknown presets" do
      assert :error = Registry.fetch("moon_kingdoms")
    end

    test "returns :error for non-string input" do
      assert :error = Registry.fetch(nil)
      assert :error = Registry.fetch(:iron_kingdoms)
    end
  end

  describe "fetch_theme/1" do
    test "returns the resolved theme map for known presets" do
      assert {:ok, theme} = Registry.fetch_theme("iron_kingdoms")
      assert theme["setting"] == "Iron Kingdoms"
      assert is_map(theme["vocabulary"])
    end

    test "returns :error for unknown preset" do
      assert :error = Registry.fetch_theme("moon_kingdoms")
    end
  end
end
