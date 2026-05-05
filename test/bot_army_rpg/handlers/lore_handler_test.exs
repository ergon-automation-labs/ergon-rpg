defmodule BotArmyRpg.Handlers.LoreHandlerTest do
  use ExUnit.Case

  alias BotArmyRpg.Handlers.LoreHandler

  setup do
    tid = "lore-handler-test-" <> Integer.to_string(:erlang.unique_integer([:positive]))
    on_exit(fn -> BotArmyRpg.LoreKeeper.forget_tenant(tid) end)

    %{tenant_id: tid}
  end

  @moduletag :handlers

  test "snapshot is empty initially", %{tenant_id: tid} do
    assert {:ok, snap} = LoreHandler.handle_snapshot(%{"payload" => %{"tenant_id" => tid}})
    assert snap["tenant_id"] == tid
    assert snap["facets"] == []
    assert snap["rollups"]["open_critical_facets"] == 0
    assert snap["schema_version"] == "1.0"
  end

  test "ingest then snapshot merges facet", %{tenant_id: tid} do
    assert {:ok, %{"ingested_facets" => 1, "dropped_facets" => 0, "tenant_id" => ^tid}} =
             LoreHandler.handle_ingest(%{
               "payload" => %{
                 "tenant_id" => tid,
                 "facets" => [
                   %{
                     "id" => "custom.warning",
                     "severity" => "warning",
                     "summary" => "test",
                     "ttl_seconds" => 3600
                   }
                 ]
               }
             })

    assert {:ok, snap} = LoreHandler.handle_snapshot(%{"payload" => %{"tenant_id" => tid}})
    assert length(snap["facets"]) == 1
    assert hd(snap["facets"])["id"] == "custom.warning"
  end
end
