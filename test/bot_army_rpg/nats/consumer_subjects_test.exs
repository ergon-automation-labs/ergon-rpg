defmodule BotArmyRpg.NATS.ConsumerSubjectsTest do
  @moduledoc """
  What the consumer advertises, and what it therefore listens to.

  This file exists because of a specific failure. `rpg.party.*` had a complete
  handler — get, add, remove, auto_populate — and **nothing anywhere subscribed to
  it**, so every call to a party subject was dropped by core NATS while the module
  that would have answered it sat in the tree looking finished. "Somebody is
  listening" is not a thing you can check by reading the handler, so it is checked
  here.

  The subjects that were already advertised are listed explicitly (rather than
  counted) so that adding a subject never rewrites this test into a lie, and
  removing one cannot pass unnoticed.
  """

  use ExUnit.Case, async: true

  @moduletag :nats

  alias BotArmyRpg.NATS.Consumer

  @already_advertised ~w(
    rpg.adventure.context.query
    rpg.campaign.get
    rpg.campaign.roster.get
    rpg.campaign.roster.update
    rpg.character.create
    rpg.character.get
    rpg.character.list
    rpg.identity.resolve
    rpg.loot.generate
    rpg.lore.snapshot
    rpg.quest.list
    rpg.roll.dice
    rpg.scene.fact.add
    rpg.scene.fact.list
    rpg.scene.narrate
    rpg.session.gather_context
    rpg.session.join
    rpg.session.leave
    rpg.session.list
    rpg.session.open
    rpg.session.state
    rpg.theme.get
    rpg.turn.whose
    rpg.world.snapshot
  )

  @party ~w(
    rpg.party.get
    rpg.party.add
    rpg.party.remove
  )

  # `rpg.party.auto_populate` is deliberately not advertised yet, and this file does
  # not assert its absence — a future fix should not have to rewrite a tripwire. The
  # handler for it exists, but the list of bot ids it recruits from is a hardcoded
  # guess (`gtd`, `llm`) that does not match the characters the fleet actually has
  # (`gtd_bot`, `llm_bot`), so registering it today would recruit a parallel ghost of
  # every companion. Wire it when that list comes from the runtime registry instead.

  test "the party's read and its two writes are advertised, so a call reaches the code that answers it" do
    advertised = Enum.map(Consumer.subjects(), & &1.subject)

    for subject <- @party do
      assert subject in advertised
    end
  end

  test "every subject the consumer already advertised is still advertised" do
    advertised = Enum.map(Consumer.subjects(), & &1.subject)

    for subject <- @already_advertised do
      assert subject in advertised
    end
  end

  test "no subject is advertised twice" do
    advertised = Enum.map(Consumer.subjects(), & &1.subject)
    assert advertised == Enum.uniq(advertised)
  end
end
