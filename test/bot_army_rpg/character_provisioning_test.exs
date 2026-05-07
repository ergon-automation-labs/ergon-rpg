defmodule BotArmyRpg.CharacterProvisioningTest do
  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.CharacterProvisioning

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock)
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
    end)

    :ok
  end

  describe "ensure_bot_character/2" do
    test "returns existing character when found" do
      tenant = "00000000-0000-0000-0000-000000000001"
      bot_id = "gtd_bot"

      existing = %{
        "id" => Ecto.UUID.generate(),
        "bot_id" => bot_id,
        "tenant_id" => tenant,
        "name" => "The Archivist"
      }

      BotArmyRpg.CharacterStoreMock
      |> expect(:get_by_bot_id, fn ^tenant, ^bot_id -> {:ok, existing} end)

      assert {:ok, ^existing} = CharacterProvisioning.ensure_bot_character(bot_id, tenant)
    end

    test "creates character when not found" do
      tenant = "00000000-0000-0000-0000-000000000001"
      bot_id = "gtd_bot"

      created = %{
        "id" => Ecto.UUID.generate(),
        "bot_id" => bot_id,
        "tenant_id" => tenant,
        "name" => "The Archivist",
        "race" => "Human",
        "class" => "Scheduler"
      }

      BotArmyRpg.ThemeStoreMock
      |> expect(:get_current, fn ^tenant -> {:ok, %{"setting" => "fantasy"}} end)

      BotArmyRpg.CharacterStoreMock
      |> expect(:get_by_bot_id, fn ^tenant, ^bot_id -> {:error, :not_found} end)
      |> expect(:create, fn payload ->
        assert payload["bot_id"] == bot_id
        assert payload["tenant_id"] == tenant
        assert payload["name"] == "The Lorekeeper"
        assert payload["race"] == "Human"
        assert payload["class"] == "Scheduler"
        {:ok, created}
      end)

      assert {:ok, ^created} = CharacterProvisioning.ensure_bot_character(bot_id, tenant)
    end
  end

  describe "get_bot_character/2" do
    test "returns character when found" do
      tenant = "00000000-0000-0000-0000-000000000001"
      bot_id = "synapse"

      existing = %{
        "id" => Ecto.UUID.generate(),
        "bot_id" => bot_id,
        "tenant_id" => tenant,
        "name" => "The Seer"
      }

      BotArmyRpg.CharacterStoreMock
      |> expect(:get_by_bot_id, fn ^tenant, ^bot_id -> {:ok, existing} end)

      assert CharacterProvisioning.get_bot_character(bot_id, tenant) == existing
    end

    test "returns nil when not found" do
      tenant = "00000000-0000-0000-0000-000000000001"
      bot_id = "unknown_bot"

      BotArmyRpg.CharacterStoreMock
      |> expect(:get_by_bot_id, fn ^tenant, ^bot_id -> {:error, :not_found} end)

      assert CharacterProvisioning.get_bot_character(bot_id, tenant) == nil
    end
  end

  describe "bot_character_name/2" do
    test "uses theme persona name when available" do
      theme = BotArmyRuntime.Personality.ThemeConfig.fantasy()
      assert CharacterProvisioning.bot_character_name("gtd_bot", theme) == "The Lorekeeper"
    end

    test "falls back to sanitized bot_id" do
      assert CharacterProvisioning.bot_character_name("bot_army_job_applications", nil) ==
               "Job Applications"
    end
  end
end
