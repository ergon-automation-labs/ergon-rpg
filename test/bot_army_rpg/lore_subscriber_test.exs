defmodule BotArmyRpg.LoreSubscriberTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.LoreSubscriber

  describe "event_to_lore_payload/2" do
    test "gossip.intent.proposed maps to facet upsert" do
      assert {:ok, %{"facets" => [facet]}} =
               LoreSubscriber.event_to_lore_payload("gossip.intent.proposed", %{
                 "event_id" => "evt-1",
                 "payload" => %{"intent_key" => "fix_email"}
               })

      assert facet["id"] == "intent.fix_email"
      assert facet["severity"] == "info"
      assert facet["summary"] =~ "fix_email"
      assert facet["ttl_seconds"] == 3_600
    end

    test "gossip.intent.resolved maps to facet drop" do
      assert {:ok, %{"facets" => [], "drops" => ["intent.fix_email"]}} =
               LoreSubscriber.event_to_lore_payload("gossip.intent.resolved", %{
                 "payload" => %{"intent_key" => "fix_email"}
               })
    end

    test "gossip.poll.broadcast maps to poll facet" do
      assert {:ok, %{"facets" => [facet]}} =
               LoreSubscriber.event_to_lore_payload("gossip.poll.broadcast", %{
                 "event_id" => "evt-2",
                 "payload" => %{"topic" => "theme_vote"}
               })

      assert facet["id"] == "poll.theme_vote"
      assert facet["ttl_seconds"] == 86_400
    end

    test "gossip.poll.resolved maps to poll drop" do
      assert {:ok, %{"facets" => [], "drops" => ["poll.theme_vote"]}} =
               LoreSubscriber.event_to_lore_payload("gossip.poll.resolved", %{
                 "payload" => %{"topic" => "theme_vote"}
               })
    end

    test "gtd.poll.broadcast maps to gtd_poll facet" do
      assert {:ok, %{"facets" => [facet]}} =
               LoreSubscriber.event_to_lore_payload("gtd.poll.broadcast", %{
                 "event_id" => "evt-3",
                 "payload" => %{"poll_id" => "abc-123"}
               })

      assert facet["id"] == "gtd_poll.abc-123"
    end

    test "gtd.poll.resolved maps to gtd_poll drop" do
      assert {:ok, %{"facets" => [], "drops" => ["gtd_poll.abc-123"]}} =
               LoreSubscriber.event_to_lore_payload("gtd.poll.resolved", %{
                 "payload" => %{"poll_id" => "abc-123"}
               })
    end

    test "unknown topic returns error" do
      assert {:error, {:unrecognized_topic, "foo.bar"}} =
               LoreSubscriber.event_to_lore_payload("foo.bar", %{})
    end
  end
end
