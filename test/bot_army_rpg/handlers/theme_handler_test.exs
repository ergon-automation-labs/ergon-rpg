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
        "payload" => %{
          "tenant_id" => "test-tenant",
          "setting" => "fantasy",
          "tone" => "whimsical",
          "mechanic" => "exploration",
          "changed_by" => "player"
        }
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
        "payload" => %{
          "tenant_id" => "test-tenant",
          "setting" => "fantasy",
          "tone" => "whimsical",
          "mechanic" => "exploration",
          "changed_by" => "player"
        }
      }

      assert {:error, _} = ThemeHandler.handle_change(message)
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
        "payload" => %{
          "setting" => "cyberpunk",
          "tone" => "hopeful",
          "mechanic" => "bounties"
        }
      }

      assert {:ok, result} = ThemeHandler.handle_change(message)
      assert result["changed_by"] == "system"
    end
  end
end
