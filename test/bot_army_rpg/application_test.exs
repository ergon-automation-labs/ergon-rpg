defmodule BotArmyRpg.ApplicationTest do
  use ExUnit.Case
  @moduletag :core

  # The application chooses its children from `Application.get_env(:bot_army_rpg, :env)`
  # at call time. It used to choose them from the OS `MIX_ENV` variable at compile time,
  # so a test build compiled in another environment started the Repo, every durable
  # store and the NATS Consumer inside the test run — which is how the party store tests
  # came to fail with `{:already_started, pid}` in the push hook while passing locally.
  # These assertions are what makes "the test run has no database and no broker behind
  # it" a property of the suite rather than a property of the shell that last compiled.
  test "the test environment starts neither the database nor the durable stores nor the consumer" do
    assert Application.get_env(:bot_army_rpg, :env) == :test
    refute Process.whereis(BotArmyRpg.Repo)
    refute Process.whereis(BotArmyRpg.PartyStore)
    refute Process.whereis(BotArmyRpg.CampaignRosterStore)
    refute Process.whereis(BotArmyRpg.NATS.Consumer)
  end
end
