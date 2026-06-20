defmodule BotArmyRpg.Handlers.SceneFactHandlerTest do
  use ExUnit.Case
  import Mox
  @moduletag :handlers

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
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
        "tenant_id" => BotArmyRuntime.Tenant.default_tenant_id()
      }

      BotArmyRpg.SceneFactStoreMock
      |> expect(:append, fn _payload -> {:ok, fact} end)

      message = %{"payload" => %{"session_id" => session_id, "content" => "The door creaks open"}}

      assert {:ok, ^fact} = BotArmyRpg.Handlers.SceneFactHandler.handle_add(message)
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
