defmodule BotArmyRpg.Handlers.IdentityHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  test "binds caller context to a normalized user id" do
    ensure_identity_store_started()

    message = %{
      "payload" => %{
        "surface" => "discord",
        "channel_id" => "123",
        "theme_id" => "resistance",
        "user_id" => "abby"
      }
    }

    assert {:ok, %{"bound" => true, "user_id" => normalized_user_id}} =
             BotArmyRpg.Handlers.IdentityHandler.handle_bind(message)

    assert is_binary(normalized_user_id)
  end

  test "reports skipped identity sync without identity bot fields" do
    ensure_identity_store_started()

    message = %{
      "payload" => %{
        "surface" => "agent",
        "client_id" => "cursor-abby",
        "user_id" => "abby"
      }
    }

    assert {:ok, %{"identity_sync" => %{"status" => "skipped"}}} =
             BotArmyRpg.Handlers.IdentityHandler.handle_bind(message)
  end

  test "returns error when user_id is missing" do
    ensure_identity_store_started()

    message = %{
      "payload" => %{
        "surface" => "agent",
        "client_id" => "cursor-abby"
      }
    }

    assert {:error, :user_id_required} = BotArmyRpg.Handlers.IdentityHandler.handle_bind(message)
  end

  test "resolves bound identity and reports last sync status" do
    ensure_identity_store_started()

    bind_message = %{
      "payload" => %{
        "surface" => "agent",
        "client_id" => "cursor-abby",
        "user_id" => "abby"
      }
    }

    assert {:ok, %{"bound" => true, "identity_sync" => %{"status" => "skipped"}}} =
             BotArmyRpg.Handlers.IdentityHandler.handle_bind(bind_message)

    resolve_message = %{
      "payload" => %{
        "surface" => "agent",
        "client_id" => "cursor-abby"
      }
    }

    assert {:ok, %{"bound" => true, "user_id" => user_id, "identity_sync" => identity_sync}} =
             BotArmyRpg.Handlers.IdentityHandler.handle_resolve(resolve_message)

    assert is_binary(user_id)
    assert identity_sync["status"] == "skipped"
  end

  test "resolve returns unbound when context has no mapping" do
    ensure_identity_store_started()

    resolve_message = %{
      "payload" => %{
        "surface" => "discord",
        "channel_id" => "999"
      }
    }

    assert {:ok, %{"bound" => false, "user_id" => nil, "identity_sync" => nil}} =
             BotArmyRpg.Handlers.IdentityHandler.handle_resolve(resolve_message)
  end

  defp ensure_identity_store_started do
    case Process.whereis(BotArmyRpg.IdentityBindingStore) do
      nil -> start_supervised!({BotArmyRpg.IdentityBindingStore, []})
      _pid -> :ok
    end
  end
end
