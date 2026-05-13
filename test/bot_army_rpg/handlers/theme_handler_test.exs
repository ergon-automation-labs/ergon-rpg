defmodule BotArmyRpg.Handlers.ThemeHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  alias BotArmyRpg.Handlers.ThemeHandler

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :theme_store)
    end)

    :ok
  end

  describe "handle_get/1" do
    test "returns current theme for tenant" do
      theme = %{
        "id" => Ecto.UUID.generate(),
        "setting" => "cyberpunk",
        "tone" => "hopeful",
        "mechanic" => "bounties",
        "is_current" => true
      }

      BotArmyRpg.ThemeStoreMock
      |> expect(:get_current, fn _tenant_id -> {:ok, theme} end)

      message = %{"payload" => %{"tenant_id" => "test-tenant"}}

      assert {:ok, result} = ThemeHandler.handle_get(message)
      assert result["setting"] == "cyberpunk"
    end

    test "returns not_found when no theme set" do
      BotArmyRpg.ThemeStoreMock
      |> expect(:get_current, fn _tenant_id -> {:error, :not_found} end)

      message = %{"payload" => %{"tenant_id" => "test-tenant"}}
      assert {:error, :not_found} = ThemeHandler.handle_get(message)
    end
  end

  describe "handle_change/1" do
    defp complete_theme_payload(overrides \\ %{}) do
      Map.merge(
        %{
          "setting" => "fantasy",
          "tone" => "whimsical",
          "mechanic" => "exploration",
          "vocabulary" => %{},
          "templates" => %{},
          "npc_personas" => %{},
          "rules" => %{}
        },
        overrides
      )
    end

    test "sets a new current theme" do
      theme = %{
        "id" => Ecto.UUID.generate(),
        "setting" => "fantasy",
        "tone" => "whimsical",
        "mechanic" => "exploration",
        "is_current" => true,
        "changed_by" => "player"
      }

      BotArmyRpg.ThemeStoreMock
      |> expect(:set_current, fn _tenant_id, _theme_data, "player" -> {:ok, theme} end)

      message = %{
        "payload" =>
          complete_theme_payload(%{
            "tenant_id" => "test-tenant",
            "changed_by" => "player"
          })
      }

      assert {:ok, result} = ThemeHandler.handle_change(message)
      assert result["setting"] == "fantasy"
    end

    test "returns error when store fails" do
      BotArmyRpg.ThemeStoreMock
      |> expect(:set_current, fn _tenant_id, _theme_data, _changed_by ->
        {:error, :database_error}
      end)

      message = %{
        "payload" =>
          complete_theme_payload(%{
            "tenant_id" => "test-tenant",
            "changed_by" => "player"
          })
      }

      assert {:error, _} = ThemeHandler.handle_change(message)
    end

    test "applies a named preset" do
      BotArmyRpg.ThemeStoreMock
      |> expect(:set_current, fn _tenant_id, theme_data, "player" ->
        assert theme_data["setting"] == "Iron Kingdoms"
        assert theme_data["vocabulary"]["attack"] == "barrage"
        assert is_map(theme_data["templates"])
        assert is_map(theme_data["npc_personas"])

        {:ok,
         %{
           "id" => Ecto.UUID.generate(),
           "setting" => theme_data["setting"],
           "tone" => theme_data["tone"],
           "is_current" => true,
           "changed_by" => "player"
         }}
      end)

      message = %{
        "payload" => %{
          "tenant_id" => "test-tenant",
          "preset" => "iron_kingdoms",
          "changed_by" => "player"
        }
      }

      assert {:ok, result} = ThemeHandler.handle_change(message)
      assert result["setting"] == "Iron Kingdoms"
    end

    test "preset overrides apply on top of the preset map" do
      BotArmyRpg.ThemeStoreMock
      |> expect(:set_current, fn _tenant_id, theme_data, _changed_by ->
        assert theme_data["setting"] == "Iron Kingdoms"
        assert theme_data["tone"] == "lighter, swashbuckling"
        assert theme_data["vocabulary"]["attack"] == "barrage"

        {:ok, %{"id" => Ecto.UUID.generate(), "setting" => "Iron Kingdoms"}}
      end)

      message = %{
        "payload" => %{
          "preset" => "iron_kingdoms",
          "tone" => "lighter, swashbuckling"
        }
      }

      assert {:ok, _} = ThemeHandler.handle_change(message)
    end

    test "rejects unknown presets without calling the store" do
      message = %{"payload" => %{"preset" => "moon_kingdoms"}}

      assert {:error, {:unknown_preset, "moon_kingdoms"}} = ThemeHandler.handle_change(message)
    end

    test "rejects theme data missing required keys" do
      message = %{
        "payload" => %{
          "setting" => "incomplete",
          "tone" => "vague"
        }
      }

      assert {:error, {:invalid_theme, missing}} = ThemeHandler.handle_change(message)
      assert "mechanic" in missing
      assert "vocabulary" in missing
    end
  end

  describe "handle_presets_list/1" do
    test "returns the auto-discovered preset list" do
      assert {:ok, %{"presets" => presets}} =
               ThemeHandler.handle_presets_list(%{"payload" => %{}})

      ik = Enum.find(presets, fn p -> p["name"] == "iron_kingdoms" end)
      refute is_nil(ik), "expected iron_kingdoms in #{inspect(presets)}"
      assert ik["display_name"] == "Iron Kingdoms"
      assert is_binary(ik["description"]) and ik["description"] != ""
      assert is_binary(ik["mechanic"])
    end

    test "defaults changed_by to system" do
      theme = %{
        "id" => Ecto.UUID.generate(),
        "setting" => "cyberpunk",
        "is_current" => true,
        "changed_by" => "system"
      }

      BotArmyRpg.ThemeStoreMock
      |> expect(:set_current, fn _tenant_id, _theme_data, "system" -> {:ok, theme} end)

      message = %{
        "payload" =>
          complete_theme_payload(%{
            "setting" => "cyberpunk",
            "tone" => "hopeful",
            "mechanic" => "bounties"
          })
      }

      assert {:ok, result} = ThemeHandler.handle_change(message)
      assert result["changed_by"] == "system"
    end
  end
end
