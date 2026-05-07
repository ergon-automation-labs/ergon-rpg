defmodule BotArmyRpg.LoreNormalizerTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.LoreNormalizer

  test "explicit facets normalize to upserts" do
    assert {:ok,
            %{
              upserts: [
                %{
                  "facet" => %{
                    "id" => "poll.open",
                    "severity" => "info",
                    "summary" => "round",
                    "ttl_seconds" => 86_400
                  }
                }
              ],
              drops: []
            }} =
             LoreNormalizer.normalize_ingest(%{
               "facets" => [
                 %{"id" => "poll.open", "severity" => "info", "summary" => "round"}
               ]
             })
  end

  test "ops_deploy failed upserts deploy.failure" do
    assert {:ok, %{upserts: [%{"facet" => f}], drops: []}} =
             LoreNormalizer.normalize_ingest(%{
               "ops_deploy" => %{
                 "bot" => "gtd",
                 "node" => "n1",
                 "triggered_by" => "jenkins",
                 "status" => "failed"
               }
             })

    assert f["id"] == "deploy.failure"
    assert f["severity"] == "warning"
  end

  test "ops_deploy success drops deploy.failure facet" do
    assert {:ok, %{upserts: [], drops: ["deploy.failure"]}} =
             LoreNormalizer.normalize_ingest(%{
               "ops_deploy" => %{
                 "bot" => "gtd",
                 "node" => "n1",
                 "triggered_by" => "jenkins",
                 "status" => "success"
               }
             })
  end

  test "system_health degraded upserts facet and drops counterpart" do
    assert {:ok, %{upserts: upserts, drops: drops}} =
             LoreNormalizer.normalize_ingest(%{
               "system_health" => %{
                 "service" => "synapse-a",
                 "status" => "degraded",
                 "uptime_seconds" => 1,
                 "last_event_age_ms" => 0
               }
             })

    [%{"facet" => f}] = upserts
    assert f["id"] =~ "health.degraded.synapse-a"
    assert "health.unhealthy.synapse-a" in drops
  end

  test "explicit facets with drops normalize correctly" do
    assert {:ok, %{upserts: [_], drops: ["intent.fix_email"]}} =
             LoreNormalizer.normalize_ingest(%{
               "facets" => [
                 %{"id" => "poll.vote", "severity" => "info", "summary" => "open"}
               ],
               "drops" => ["intent.fix_email", ""]
             })
  end

  test "unknown ingest shape errors" do
    assert LoreNormalizer.normalize_ingest(%{"foo" => 1}) == {:error, :unknown_ingest_shape}
  end
end
