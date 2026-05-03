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

    test "filters characters by user_id when provided as UUID" do
      user_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      characters = [
        %{"id" => Ecto.UUID.generate(), "name" => "Aria", "user_id" => user_id},
        %{"id" => Ecto.UUID.generate(), "name" => "Borin", "user_id" => other_user_id}
      ]

      BotArmyRpg.CharacterStoreMock
      |> expect(:list, fn _tenant_id -> {:ok, characters} end)

      message = %{"payload" => %{"user_id" => user_id}}

      assert {:ok, [filtered]} = BotArmyRpg.Handlers.CharacterHandler.handle_list(message)
      assert filtered["user_id"] == user_id
      assert filtered["name"] == "Aria"
    end

    test "filters characters by user_id when provided as stable string" do
      source_user = "abby"
      hash = :crypto.hash(:sha256, source_user)
      <<uuid_int::128>> = binary_part(hash, 0, 16)
      normalized_user_id = <<uuid_int::128>> |> Ecto.UUID.cast() |> elem(1)

      characters = [
        %{"id" => Ecto.UUID.generate(), "name" => "Aria", "user_id" => normalized_user_id},
        %{"id" => Ecto.UUID.generate(), "name" => "Borin", "user_id" => Ecto.UUID.generate()}
      ]

      BotArmyRpg.CharacterStoreMock
      |> expect(:list, fn _tenant_id -> {:ok, characters} end)

      message = %{"payload" => %{"user_id" => source_user}}

      assert {:ok, [filtered]} = BotArmyRpg.Handlers.CharacterHandler.handle_list(message)
      assert filtered["user_id"] == normalized_user_id
      assert filtered["name"] == "Aria"
    end
  end

  describe "identity binding fallback" do
    test "uses bound identity for create when user_id is not provided" do
      ensure_identity_store_started()

      bind_message = %{
        "payload" => %{
          "surface" => "agent",
          "client_id" => "cursor-abby",
          "user_id" => "abby"
        }
      }

      assert {:ok, %{"bound" => true, "user_id" => bound_user_id}} =
               BotArmyRpg.Handlers.IdentityHandler.handle_bind(bind_message)

      character = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Aria",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id(),
        "user_id" => bound_user_id
      }

      BotArmyRpg.CharacterStoreMock
      |> expect(:create, fn payload ->
        assert payload["user_id"] == bound_user_id
        {:ok, character}
      end)

      message = %{
        "payload" => %{
          "name" => "Aria",
          "surface" => "agent",
          "client_id" => "cursor-abby"
        }
      }

      assert {:ok, %{"user_id" => ^bound_user_id}} =
               BotArmyRpg.Handlers.CharacterHandler.handle_create(message)
    end
  end

  defp ensure_identity_store_started do
    case Process.whereis(BotArmyRpg.IdentityBindingStore) do
      nil -> start_supervised!({BotArmyRpg.IdentityBindingStore, []})
      _pid -> :ok
    end
  end
end
