defmodule BotArmyRpg.Handlers.SessionHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  setup :verify_on_exit!

  describe "handle_start/1" do
    test "starts a new session" do
      session = %{
        "id" => Ecto.UUID.generate(),
        "status" => "active",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SessionStoreMock
      |> expect(:create, fn _payload -> {:ok, session} end)

      message = %{"payload" => %{}}

      assert {:ok, ^session} = BotArmyRpg.Handlers.SessionHandler.handle_start(message)
    end
  end

  describe "handle_pause/1" do
    test "pauses an active session" do
      session_id = Ecto.UUID.generate()

      session = %{
        "id" => session_id,
        "status" => "paused",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SessionStoreMock
      |> expect(:update, fn _tenant_id, ^session_id, %{"status" => "paused"} -> {:ok, session} end)

      message = %{"payload" => %{"session_id" => session_id}}

      assert {:ok, ^session} = BotArmyRpg.Handlers.SessionHandler.handle_pause(message)
    end
  end

  describe "handle_end/1" do
    test "ends a session" do
      session_id = Ecto.UUID.generate()

      session = %{
        "id" => session_id,
        "status" => "ended",
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SessionStoreMock
      |> expect(:update, fn _tenant_id, ^session_id, %{"status" => "ended"} -> {:ok, session} end)

      message = %{"payload" => %{"session_id" => session_id}}

      assert {:ok, ^session} = BotArmyRpg.Handlers.SessionHandler.handle_end(message)
    end
  end
end
