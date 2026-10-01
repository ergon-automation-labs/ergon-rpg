defmodule BotArmyRpg.PartyNarrationTest do
  @moduledoc """
  What a narrator is asked, and on what subject.

  This event is the contract a narrator bot answers to, and when a party has a narrator the
  GM writes no fact for the turn — so the event is the only place the turn's actor, action
  and resolution exist for her. The payload is pinned here rather than left to be read out
  of the code that publishes it.
  """

  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.PartyNarration

  defmodule StubPublisher do
    @moduledoc false
    def publish(subject, payload, opts) do
      send(self(), {:published, subject, payload, opts})
      :ok
    end
  end

  @member %{"character_id" => "c-narrator", "bot_id" => "companion_bot", "role" => "narrator"}

  @session %{
    "id" => "00000000-0000-0000-0000-0000000000se",
    "scene_description" => "a hall with one long table",
    "metadata" => %{"turn_state" => %{"round" => 3}}
  }

  @turn %{
    "actor" => %{"character_id" => "c-actor", "name" => "The Lorekeeper"},
    "action" => %{"action_type" => "attack", "description" => "strikes at the dark"},
    "resolution" => %{"outcome" => "success", "total" => 14, "dc" => 12}
  }

  setup do
    Application.put_env(:bot_army_rpg, :nats_publisher, StubPublisher)

    on_exit(fn -> Application.delete_env(:bot_army_rpg, :nats_publisher) end)

    :ok
  end

  describe "payload/3" do
    test "names her, and carries the actor, the action and the resolution" do
      payload = PartyNarration.payload(@member, @session, @turn)

      assert payload["bot_id"] == "companion_bot"
      assert payload["character_id"] == "c-narrator"
      assert payload["session_id"] == @session["id"]
      assert payload["scene_description"] == "a hall with one long table"
      assert payload["round"] == 3
      assert payload["actor"] == @turn["actor"]
      assert payload["action"] == @turn["action"]
      assert payload["resolution"] == @turn["resolution"]
    end

    test "a session with no turn state reports no round rather than a made-up one" do
      payload = PartyNarration.payload(@member, Map.delete(@session, "metadata"), @turn)

      assert payload["round"] == nil
    end
  end

  describe "the note an ask leaves" do
    test "names whom it asked, and reads that name back" do
      content = PartyNarration.note_content(@member)
      fact = %{"content" => content, "category" => PartyNarration.asked_category()}

      assert content == "[narration_asked] companion_bot"
      assert PartyNarration.asked?(fact)
      assert PartyNarration.asked_of(fact) == "companion_bot"
    end

    test "a turn is not a note: the category decides it, not the opening word" do
      marked_prose = %{
        "content" => "[narration_asked] is what I would have said",
        "category" => "dialogue"
      }

      refute PartyNarration.asked?(marked_prose)
    end

    test "a fact that is nobody's note names nobody" do
      assert PartyNarration.asked_of(%{"content" => "the door closed"}) == nil
      assert PartyNarration.asked_of(%{"content" => ""}) == nil
      assert PartyNarration.asked_of(%{"content" => "[narration_asked]   "}) == nil
      assert PartyNarration.asked_of(%{}) == nil
    end
  end

  describe "ask/4" do
    test "is published on the narrator's subject, in the tenant, with the payload" do
      assert :ok =
               PartyNarration.ask(
                 @member,
                 @session,
                 "00000000-0000-0000-0000-000000000001",
                 @turn
               )

      assert_received {:published, subject, payload, opts}

      assert subject == PartyNarration.subject()
      assert subject == "rpg.narration.your_turn"
      assert opts[:tenant_id] == "00000000-0000-0000-0000-000000000001"
      assert payload == PartyNarration.payload(@member, @session, @turn)
    end
  end
end
