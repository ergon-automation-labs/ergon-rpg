defmodule BotArmyRpg.Handlers.SceneFactHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :session_store)
    end)

    :ok
  end

  describe "handle_add/1" do
    test "appends a scene fact" do
      session_id = Ecto.UUID.generate()

      fact = %{
        "id" => Ecto.UUID.generate(),
        "session_id" => session_id,
        "content" => "The door creaks open",
        "tenant_id" => BotArmyLibraryRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SceneFactStoreMock
      |> expect(:append, fn _payload -> {:ok, fact} end)

      # A turn is the window being used, so the window's clock moves with it.
      BotArmyRpg.SessionStoreMock
      |> expect(:touch, fn tenant, ^session_id ->
        assert tenant == BotArmyLibraryRuntime.Tenant.default_tenant_id()
        {:ok, %{"id" => session_id}}
      end)

      message = %{"payload" => %{"session_id" => session_id, "content" => "The door creaks open"}}

      assert {:ok, ^fact} = BotArmyRpg.Handlers.SceneFactHandler.handle_add(message)
    end

    test "a window whose clock could not move still stores the turn" do
      session_id = Ecto.UUID.generate()

      fact = %{"id" => Ecto.UUID.generate(), "session_id" => session_id, "content" => "a line"}

      expect(BotArmyRpg.SceneFactStoreMock, :append, fn _payload -> {:ok, fact} end)

      expect(BotArmyRpg.SessionStoreMock, :touch, fn _tenant, ^session_id ->
        {:error, :not_found}
      end)

      # Best effort: the turn is stored and told so; only the ordering is left stale,
      # and that is logged rather than hidden.
      assert {:ok, ^fact} =
               BotArmyRpg.Handlers.SceneFactHandler.handle_add(%{
                 "payload" => %{"session_id" => session_id, "content" => "a line"}
               })
    end
  end

  describe "handle_list/1" do
    test "lists facts for a session" do
      session_id = Ecto.UUID.generate()

      facts = [
        %{"id" => Ecto.UUID.generate(), "session_id" => session_id, "content" => "A shadow moves"}
      ]

      BotArmyRpg.SceneFactStoreMock
      |> expect(:list_for_session, fn _tenant_id, ^session_id -> {:ok, facts} end)

      message = %{"payload" => %{"session_id" => session_id}}

      assert {:ok, ^facts} = BotArmyRpg.Handlers.SceneFactHandler.handle_list(message)
    end
  end
end
