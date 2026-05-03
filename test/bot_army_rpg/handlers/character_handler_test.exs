defmodule BotArmyRpg.Handlers.CharacterHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  setup :verify_on_exit!

  describe "handle_create/1" do
    test "creates a character and publishes event" do
      character = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Aria",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.CharacterStoreMock
      |> expect(:create, fn _payload -> {:ok, character} end)

      message = %{
        "payload" => %{
          "name" => "Aria",
          "race" => "Elf",
          "class" => "Wizard"
        }
      }

      assert {:ok, ^character} = BotArmyRpg.Handlers.CharacterHandler.handle_create(message)
    end

    test "returns error when store fails" do
      BotArmyRpg.CharacterStoreMock
      |> expect(:create, fn _payload -> {:error, :database_error} end)

      message = %{"payload" => %{"name" => "Aria"}}

      assert {:error, :database_error} =
               BotArmyRpg.Handlers.CharacterHandler.handle_create(message)
    end
  end

  describe "handle_get/1" do
    test "retrieves a character" do
      character_id = Ecto.UUID.generate()

      character = %{
        "id" => character_id,
        "name" => "Aria",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.CharacterStoreMock
      |> expect(:get, fn _tenant_id, ^character_id -> {:ok, character} end)

      message = %{"payload" => %{"character_id" => character_id}}

      assert {:ok, ^character} = BotArmyRpg.Handlers.CharacterHandler.handle_get(message)
    end

    test "returns not_found for missing character" do
      BotArmyRpg.CharacterStoreMock
      |> expect(:get, fn _tenant_id, _character_id -> {:error, :not_found} end)

      message = %{"payload" => %{"character_id" => Ecto.UUID.generate()}}

      assert {:error, :not_found} = BotArmyRpg.Handlers.CharacterHandler.handle_get(message)
    end
  end

  describe "handle_list/1" do
    test "lists characters for tenant" do
      characters = [%{"id" => Ecto.UUID.generate(), "name" => "Aria"}]

      BotArmyRpg.CharacterStoreMock
      |> expect(:list, fn _tenant_id -> {:ok, characters} end)

      message = %{"payload" => %{}}

      assert {:ok, ^characters} = BotArmyRpg.Handlers.CharacterHandler.handle_list(message)
    end
  end
end
