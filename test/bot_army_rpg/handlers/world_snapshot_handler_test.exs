defmodule BotArmyRpg.Handlers.WorldSnapshotHandlerTest do
  @moduledoc """
  The snapshot reads one thing, and its three failures are not the same failure.

  `rpg.world.snapshot` had no test. What it does when the theme read comes back empty,
  absent, or broken is the whole contract: a tenant with nothing written yet has an *empty*
  theme (a world with no lore is still a world), while a store that could not answer at all
  is a **refusal**. Rendering those two the same way is how a broken read becomes a silent
  "nothing here" — the failure mode this suite refuses everywhere else.
  """

  use ExUnit.Case
  @moduletag :handlers

  import Mox

  alias BotArmyRpg.Handlers.WorldSnapshotHandler

  @tenant "00000000-0000-0000-0000-000000000001"
  @default_tenant "00000000-0000-0000-0000-000000000001"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock)

    on_exit(fn -> Application.delete_env(:bot_army_rpg, :theme_store) end)

    :ok
  end

  test "a theme on file becomes the snapshot's campaign_theme" do
    expect(BotArmyRpg.ThemeStoreMock, :get_current, fn @tenant ->
      {:ok, %{"setting" => "Liberty City", "tone" => "noir"}}
    end)

    assert {:ok, snapshot} =
             WorldSnapshotHandler.handle_snapshot(%{"tenant_id" => @tenant, "user_id" => "u1"})

    assert snapshot["campaign_theme"] == %{"setting" => "Liberty City", "tone" => "noir"}
    assert snapshot["tenant_id"] == @tenant
    assert snapshot["user_id"] == "u1"
    assert is_binary(snapshot["timestamp"])
    assert is_map(snapshot["system_metadata"])
  end

  test "a tenant with no theme yet gets an empty theme, not a refusal" do
    stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:error, :not_found} end)

    assert {:ok, snapshot} =
             WorldSnapshotHandler.handle_snapshot(%{"tenant_id" => @tenant, "user_id" => "u1"})

    assert snapshot["campaign_theme"] == %{}
  end

  test "a store that could not answer is a refusal" do
    stub(BotArmyRpg.ThemeStoreMock, :get_current, fn _tenant -> {:error, :timeout} end)

    assert {:error, "theme_load_failed"} =
             WorldSnapshotHandler.handle_snapshot(%{"tenant_id" => @tenant, "user_id" => "u1"})
  end

  test "no tenant names the default, and no user is anonymous" do
    stub(BotArmyRpg.ThemeStoreMock, :get_current, fn tenant ->
      assert tenant == @default_tenant
      {:ok, %{}}
    end)

    assert {:ok, snapshot} = WorldSnapshotHandler.handle_snapshot(%{})
    assert snapshot["tenant_id"] == @default_tenant
    assert snapshot["user_id"] == "anonymous"
  end
end
