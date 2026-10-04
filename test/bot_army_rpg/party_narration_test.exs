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

  defmodule StubSceneFactStore do
    @moduledoc false
    def append(payload) do
      send(self(), {:appended, payload})
      {:ok, Map.put(payload, "id", "note-1")}
    end
  end

  defmodule FailingSceneFactStore do
    @moduledoc false
    def append(_payload), do: {:error, :database_unavailable}
  end

  defmodule FailingPublisher do
    @moduledoc false
    def publish(_subject, _payload, _opts), do: {:error, :no_connection_manager}
  end

  @member %{"character_id" => "c-narrator", "bot_id" => "companion_bot", "role" => "narrator"}

  defp chat_note(bot_id), do: note("chat", bot_id)
  defp turn_note(bot_id), do: note("turn", bot_id)

  defp note(kind, bot_id) do
    %{
      "content" => PartyNarration.note_content(%{"bot_id" => bot_id}, kind),
      "category" => PartyNarration.asked_category()
    }
  end

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
    Application.put_env(:bot_army_rpg, :scene_fact_store, StubSceneFactStore)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :nats_publisher)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
    end)

    :ok
  end

  describe "payload/3" do
    test "names her, and carries the actor, the action and the resolution" do
      payload = PartyNarration.payload(@member, @session, @turn)

      assert payload["kind"] == "turn"
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
    test "names what kind of ask it was and whom it asked, and reads both back" do
      content = PartyNarration.note_content(@member, PartyNarration.chat_kind())
      fact = %{"content" => content, "category" => PartyNarration.asked_category()}

      assert content == "[narration_asked] chat companion_bot"
      assert PartyNarration.asked?(fact)
      assert PartyNarration.asked_of(fact) == "companion_bot"
      assert PartyNarration.asked_kind(fact) == "chat"

      # A turn's note is the same note in the other lane. Both are notes, and the kind is
      # what tells the lanes apart when the window's round is read off them.
      turn = %{
        "content" => PartyNarration.note_content(@member),
        "category" => PartyNarration.asked_category()
      }

      assert turn["content"] == "[narration_asked] turn companion_bot"
      assert PartyNarration.asked_of(turn) == "companion_bot"
      assert PartyNarration.asked_kind(turn) == PartyNarration.turn_kind()
    end

    test "a note an older rpg wrote says which member and nothing else" do
      # The kind was added after the chat lane: a note from before it cannot say which
      # lane asked, so it is read as a turn rather than as a lane nobody recorded.
      older = %{
        "content" => "[narration_asked] companion_bot",
        "category" => PartyNarration.asked_category()
      }

      assert PartyNarration.asked_of(older) == "companion_bot"
      assert PartyNarration.asked_kind(older) == PartyNarration.turn_kind()
    end

    test "a member whose name is a kind is still read as the member" do
      # `turn` with nobody after it is a member called `turn`, not a kind and no name.
      fact = %{
        "content" => PartyNarration.note_content(%{"bot_id" => "turn"}, "chat"),
        "category" => PartyNarration.asked_category()
      }

      assert PartyNarration.asked_of(fact) == "turn"
    end

    test "a turn is not a note: the category decides it, not the opening word" do
      marked_prose = %{
        "content" => "[narration_asked] is what I would have said",
        "category" => "dialogue"
      }

      refute PartyNarration.asked?(marked_prose)
      assert PartyNarration.asked_of(marked_prose) == nil
      assert PartyNarration.asked_kind(marked_prose) == nil
    end

    test "a fact that is nobody's note names nobody" do
      assert PartyNarration.asked_of(%{"content" => "the door closed"}) == nil
      assert PartyNarration.asked_of(%{"content" => ""}) == nil
      assert PartyNarration.asked_of(%{"content" => "[narration_asked]   "}) == nil
      assert PartyNarration.asked_of(%{}) == nil
      assert PartyNarration.asked_kind(%{}) == nil
    end
  end

  describe "last_asked/2" do
    test "names the member the newest chat note asked, not the newest note of any lane" do
      facts = [
        chat_note("gtd_bot"),
        turn_note("companion_bot"),
        %{"content" => "the hall falls quiet", "category" => "narration"}
      ]

      assert PartyNarration.last_asked(facts, PartyNarration.chat_kind()) == "gtd_bot"
      assert PartyNarration.last_asked(facts, PartyNarration.turn_kind()) == "companion_bot"
    end

    test "a lane that has asked nobody yet names nobody" do
      assert PartyNarration.last_asked([turn_note("companion_bot")], "chat") == nil
      assert PartyNarration.last_asked([], "chat") == nil
    end

    test "a history that is not a list of facts names nobody" do
      assert PartyNarration.last_asked(nil, "chat") == nil
      assert PartyNarration.last_asked(%{}, "chat") == nil
    end

    test "a note with no kind in it is read as a turn, so it moves no chat round" do
      older = %{
        "content" => "[narration_asked] companion_bot",
        "category" => PartyNarration.asked_category()
      }

      assert PartyNarration.last_asked([older], "chat") == nil
      assert PartyNarration.last_asked([older], "turn") == "companion_bot"
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

    test "leaves its own note, so no caller can publish an ask a table never sees" do
      assert :ok =
               PartyNarration.ask(
                 @member,
                 @session,
                 "00000000-0000-0000-0000-000000000001",
                 @turn
               )

      assert_received {:appended, note}
      assert note["content"] == "[narration_asked] turn companion_bot"
      assert note["category"] == PartyNarration.asked_category()
      assert note["session_id"] == @session["id"]
    end
  end

  describe "chat_payload/3 and ask_chat/4" do
    @line %{
      "content" => "is anybody in there",
      "source" => "operator",
      "session_id" => @session["id"],
      "category" => "dialogue"
    }

    test "carries the line and who said it, and no turn's material" do
      payload = PartyNarration.chat_payload(@member, @session["id"], @line)

      assert payload == %{
               "kind" => "chat",
               "session_id" => @session["id"],
               "character_id" => "c-narrator",
               "bot_id" => "companion_bot",
               "content" => "is anybody in there",
               "speaker" => "operator"
             }

      # A chat ask is not a turn: there is no action to narrate, and the far end decides
      # what to write from the kind rather than from which fields happen to be present.
      refute Map.has_key?(payload, "actor")
      refute Map.has_key?(payload, "action")
      refute Map.has_key?(payload, "resolution")
    end

    test "is published on the same subject a turn's ask uses, and noted in the chat lane" do
      assert :ok =
               PartyNarration.ask_chat(
                 @member,
                 @session["id"],
                 "00000000-0000-0000-0000-000000000001",
                 @line
               )

      assert_received {:published, subject, payload, opts}

      assert subject == "rpg.narration.your_turn"
      assert opts[:tenant_id] == "00000000-0000-0000-0000-000000000001"
      assert payload == PartyNarration.chat_payload(@member, @session["id"], @line)

      assert_received {:appended, note}
      assert note["content"] == "[narration_asked] chat companion_bot"
      assert note["category"] == PartyNarration.asked_category()
    end

    test "an ask the bus would not take leaves no note, because nobody was asked" do
      Application.put_env(:bot_army_rpg, :nats_publisher, FailingPublisher)

      assert {:error, :no_connection_manager} =
               PartyNarration.ask_chat(
                 @member,
                 @session["id"],
                 "00000000-0000-0000-0000-000000000001",
                 @line
               )

      refute_received {:appended, _note}
    end
  end

  describe "note_the_ask/4" do
    test "writes the note the pending reading is built from, signed by the machinery" do
      assert :ok =
               PartyNarration.note_the_ask(
                 @member,
                 @session["id"],
                 "00000000-0000-0000-0000-000000000001"
               )

      assert_received {:appended, note}

      assert note["content"] == "[narration_asked] turn companion_bot"
      assert note["category"] == PartyNarration.asked_category()
      assert note["source"] == "system"
      assert note["session_id"] == @session["id"]
      assert note["tenant_id"] == "00000000-0000-0000-0000-000000000001"

      # The note this writes is the note the window's reader recognises: round-tripped
      # here rather than assumed, because a note no reader can find is not a note.
      assert PartyNarration.asked?(note)
      assert PartyNarration.asked_of(note) == "companion_bot"
      assert PartyNarration.asked_kind(note) == PartyNarration.turn_kind()
    end

    test "a note that could not be written is the bookkeeping failing, not the ask" do
      Application.put_env(:bot_army_rpg, :scene_fact_store, FailingSceneFactStore)

      assert :ok =
               PartyNarration.note_the_ask(
                 @member,
                 @session["id"],
                 "00000000-0000-0000-0000-000000000001",
                 PartyNarration.chat_kind()
               )
    end
  end
end
