defmodule BotArmyRpg.PartyChatTest do
  @moduledoc """
  When a line in the window's chat is handed to someone.

  The window used to be one-way: only a resolved turn asked a narrator for words, so a line
  typed into it asked nobody. This pins the rule that closes that — who answers, which facts
  are worth an answer, and what happens to the line when nobody can be.

  Who answers is the window's answer, and so is the round: the members come from the session
  the line landed in, and the cursor from the window's own notes. So the reads here are the
  session and the facts, and a test that leaves one without an expectation is saying the ask
  never made that read.

  The ask is pinned by its payload rather than by reading the code that publishes it: the far
  end is a different application (the companion's `PartyNarrator`), so the wire shape is the
  contract between them.
  """

  use ExUnit.Case
  @moduletag :core

  import Mox

  alias BotArmyRpg.PartyChat

  defmodule StubPublisher do
    @moduledoc false
    def publish(subject, payload, opts) do
      send(self(), {:published, subject, payload, opts})
      :ok
    end
  end

  defmodule FailingPublisher do
    @moduledoc false
    def publish(_subject, _payload, _opts), do: {:error, :no_connection_manager}
  end

  @tenant "00000000-0000-0000-0000-000000000001"
  @session "00000000-0000-0000-0000-00000000000e"

  # Two members at the table, ordered by character id so that the round is a fact about the
  # window rather than about the order a map happened to come back in.
  @table %{"c-arda" => "arda_bot", "c-bram" => "bram_bot"}

  @line %{
    "id" => "f1",
    "session_id" => @session,
    "content" => "hello in there",
    "source" => "operator",
    "category" => "dialogue"
  }

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :nats_publisher, StubPublisher)
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :nats_publisher)
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
    end)

    :ok
  end

  defp expect_window(characters) do
    expect(BotArmyRpg.SessionStoreMock, :get, fn @tenant, @session ->
      {:ok, %{"id" => @session, "character_ids" => characters}}
    end)
  end

  defp expect_history(facts) do
    expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn @tenant, @session ->
      {:ok, facts}
    end)
  end

  defp chat_note(bot_id) do
    %{
      "content" => "[narration_asked] chat #{bot_id}",
      "category" => "narration_asked",
      "source" => "system"
    }
  end

  # The note is written through the scene-fact store, so a test that expects one holds it:
  # an ask that wrote none would be a Mox call with no expectation, and the test would say so.
  defp expect_note do
    expect(BotArmyRpg.SceneFactStoreMock, :append, fn note ->
      send(self(), {:noted, note})
      {:ok, Map.put(note, "id", "note-1")}
    end)
  end

  describe "askable?/1" do
    test "a line somebody said is worth an answer" do
      assert PartyChat.askable?(@line)
      assert PartyChat.askable?(%{"content" => "hi", "source" => "gtd_bot"})
    end

    test "the machinery's own note is not a line anybody said" do
      refute PartyChat.askable?(%{"content" => "hi", "source" => "system"})
    end

    test "the GM's prose is rpg's own answer, so nobody is asked for it again" do
      refute PartyChat.askable?(%{"content" => "The hall falls quiet", "source" => "gm"})
    end

    test "nothing said is not a line: blank and missing content are not answered" do
      refute PartyChat.askable?(%{"content" => "", "source" => "operator"})
      refute PartyChat.askable?(%{"content" => "   ", "source" => "operator"})
      refute PartyChat.askable?(%{"content" => nil, "source" => "operator"})
      refute PartyChat.askable?(%{"source" => "operator"})
      refute PartyChat.askable?(%{})
      refute PartyChat.askable?("hello")
    end
  end

  describe "maybe_ask/3" do
    test "the first line of a conversation is handed to the first member at the table" do
      expect_window(@table)
      expect_history([])
      expect_note()

      assert {:asked, %{"bot_id" => "arda_bot"}} = PartyChat.maybe_ask(@tenant, @session, @line)

      assert_received {:published, subject, payload, opts}
      assert subject == "rpg.narration.your_turn"
      assert opts[:tenant_id] == @tenant

      assert payload == %{
               "kind" => "chat",
               "session_id" => @session,
               "character_id" => "c-arda",
               "bot_id" => "arda_bot",
               "content" => "hello in there",
               "speaker" => "operator"
             }

      # The note is what the window's pending reading is built from, and it says which lane
      # asked: the round is read off the chat notes only, so this is what keeps a turn's ask
      # from moving it.
      assert_receive {:noted, note}
      assert note["content"] == "[narration_asked] chat arda_bot"
      assert note["category"] == "narration_asked"
      assert note["source"] == "system"
      assert note["session_id"] == @session
      assert note["tenant_id"] == @tenant
    end

    test "the round moves on: the member after the one the chat asked last answers" do
      expect_window(@table)
      expect_history([chat_note("arda_bot")])
      expect_note()

      assert {:asked, %{"bot_id" => "bram_bot"}} = PartyChat.maybe_ask(@tenant, @session, @line)

      assert_received {:published, _subject, %{"bot_id" => "bram_bot"}, _opts}
      assert_receive {:noted, %{"content" => "[narration_asked] chat bram_bot"}}
    end

    test "a turn's ask does not move the chat's round" do
      # The table resolved a turn in between, and its note names the member the *turn* went
      # to. Reading that as a chat ask would hand this line to the member after `bram_bot`
      # instead of the member after the last line the chat actually asked.
      expect_window(@table)

      expect_history([
        chat_note("arda_bot"),
        %{"content" => "[narration_asked] turn bram_bot", "category" => "narration_asked"}
      ])

      expect_note()

      assert {:asked, %{"bot_id" => "bram_bot"}} = PartyChat.maybe_ask(@tenant, @session, @line)
    end

    test "the member who wrote the line is walked past, and their words are not asked back" do
      expect_window(@table)
      expect_history([])
      expect_note()

      line = Map.put(@line, "source", "arda_bot")

      assert {:asked, %{"bot_id" => "bram_bot"}} = PartyChat.maybe_ask(@tenant, @session, line)
    end

    test "a table of one talking to itself has nobody left to ask" do
      expect_window(%{"c-arda" => "arda_bot"})
      expect_history([])

      line = Map.put(@line, "source", "arda_bot")

      assert :own_words = PartyChat.maybe_ask(@tenant, @session, line)
      refute_received {:published, _, _, _}
      refute_received {:noted, _}
    end

    test "a window nobody has been put in answers nobody, and reads no history to say so" do
      # No history expectation: an empty table has no round to read a cursor for, so a read
      # of the facts here would be a Mox call with no expectation and the test would fail.
      expect_window(%{})

      assert :no_members = PartyChat.maybe_ask(@tenant, @session, @line)
      refute_received {:published, _, _, _}
      refute_received {:noted, _}
    end

    test "a window whose characters name no bot answers nobody" do
      expect_window(%{"c-arda" => nil, "c-bram" => 42})

      assert :no_members = PartyChat.maybe_ask(@tenant, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "a window that cannot be read asks nobody, and is not read as a window with nobody in it" do
      expect(BotArmyRpg.SessionStoreMock, :get, fn @tenant, @session -> {:error, :timeout} end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "a history that cannot be read asks nobody, because the round is a reading" do
      # Whose turn it is *is* the window's history. Starting the round over because the
      # history could not be read would hand the line to someone the table already answered
      # as, and saying so is better than guessing.
      expect_window(@table)

      expect(BotArmyRpg.SceneFactStoreMock, :list_for_session, fn @tenant, @session ->
        {:error, :timeout}
      end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "a store whose process is dead asks nobody rather than taking the line down with it" do
      expect(BotArmyRpg.SessionStoreMock, :get, fn @tenant, @session -> exit(:noproc) end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @session, @line)
    end

    test "a session that is not a window at all asks nobody" do
      expect(BotArmyRpg.SessionStoreMock, :get, fn @tenant, @session -> {:ok, "not a session"} end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @session, @line)
    end

    test "an ask the bus would not take leaves no note, because nobody was asked" do
      expect_window(@table)
      expect_history([])

      # A stub, not an expectation: this test is about the note *not* being written, and a
      # note that was written anyway would be seen by the `refute_received` below.
      stub(BotArmyRpg.SceneFactStoreMock, :append, fn note ->
        send(self(), {:noted, note})
        {:ok, note}
      end)

      Application.put_env(:bot_army_rpg, :nats_publisher, FailingPublisher)

      assert {:error, :no_connection_manager} = PartyChat.maybe_ask(@tenant, @session, @line)

      refute_received {:noted, _}
    end

    test "a line that names no window is not asked about" do
      # No window read and no history read at all: there is not enough of an ask to make.
      assert :no_window = PartyChat.maybe_ask(@tenant, nil, @line)
      assert :no_window = PartyChat.maybe_ask(@tenant, "", @line)
      assert :no_window = PartyChat.maybe_ask(@tenant, 42, @line)
    end

    test "a fact that is not a line never reaches the table" do
      note = %{"content" => "[narration_asked] chat arda_bot", "source" => "system"}
      gm = %{"content" => "The hall falls quiet", "source" => "gm"}

      assert :not_a_turn = PartyChat.maybe_ask(@tenant, @session, note)
      assert :not_a_turn = PartyChat.maybe_ask(@tenant, @session, gm)
    end
  end
end
