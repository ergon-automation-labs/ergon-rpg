defmodule BotArmyRpg.PartyChatTest do
  @moduledoc """
  When a line in the window's chat is handed to someone.

  The window used to be one-way: only a resolved turn asked a narrator for words, so a line
  typed into it asked nobody. This pins the rule that closes that — who is asked, which
  facts are worth an answer, and what happens to the line when nobody can be.

  The ask is pinned by its payload rather than by reading the code that publishes it: the
  far end is a different application (the companion's `PartyNarrator`), so the wire shape is
  the contract between them.
  """

  use ExUnit.Case
  @moduletag :core

  import Mox

  alias BotArmyRpg.{Identity, PartyChat}

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
  @user "00000000-0000-0000-0000-000000000002"
  @session "00000000-0000-0000-0000-00000000000e"

  @narrator %{"character_id" => "c-narrator", "bot_id" => "companion_bot", "role" => "narrator"}
  @member %{"character_id" => "c-member", "bot_id" => "gtd_bot", "role" => "companion"}

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
    Application.put_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStoreMock)
    Application.put_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :nats_publisher)
      Application.delete_env(:bot_army_rpg, :party_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
    end)

    :ok
  end

  defp party_with(members) do
    %{"name" => "The Adventuring Party", "members" => members, "created_at" => "2026-09-29"}
  end

  defp expect_party(members) do
    expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
      {:ok, party_with(members)}
    end)
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

    test "the GM's prose is rpg's own answer, so she is not asked for it again" do
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

  describe "maybe_ask/4" do
    test "a line in a window whose party names a narrator is handed to her, and noted" do
      expect_party([@member, @narrator])
      expect_note()

      assert {:asked, @narrator} = PartyChat.maybe_ask(@tenant, @user, @session, @line)

      assert_received {:published, subject, payload, opts}
      assert subject == "rpg.narration.your_turn"
      assert opts[:tenant_id] == @tenant

      assert payload == %{
               "kind" => "chat",
               "session_id" => @session,
               "character_id" => "c-narrator",
               "bot_id" => "companion_bot",
               "content" => "hello in there",
               "speaker" => "operator"
             }

      # The note is what the window's pending reading is built from, so it says whom it
      # asked and is signed by the machinery rather than by a person in the scene.
      assert_receive {:noted, note}
      assert note["content"] == "[narration_asked] companion_bot"
      assert note["category"] == "narration_asked"
      assert note["source"] == "system"
      assert note["session_id"] == @session
      assert note["tenant_id"] == @tenant
    end

    test "a party that names no narrator answers nobody" do
      expect_party([@member])

      assert :no_narrator = PartyChat.maybe_ask(@tenant, @user, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "a window with no party at all answers nobody" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user -> {:error, :not_found} end)

      assert :no_narrator = PartyChat.maybe_ask(@tenant, @user, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "her own words are the answer, so asking her again would be the loop" do
      expect_party([@narrator])

      assert :own_words =
               PartyChat.maybe_ask(
                 @tenant,
                 @user,
                 @session,
                 Map.put(@line, "source", "companion_bot")
               )

      refute_received {:published, _, _, _}
    end

    test "the identity a party is recruited under keys the same party the routes do" do
      # The dashboard recruits under the name an operator uses for herself, and the routes
      # normalize it before they key the store. This read must key the same row, or the
      # chat ask would look for a party under a name no row is stored under.
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, user_id ->
        assert user_id == Identity.normalize_user_id("abby")
        {:ok, party_with([@narrator])}
      end)

      expect_note()

      assert {:asked, @narrator} = PartyChat.maybe_ask(@tenant, "abby", @session, @line)
    end

    test "a party that cannot be read asks nobody, and is not read as a party with no narrator" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user -> {:error, :timeout} end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @user, @session, @line)
      refute_received {:published, _, _, _}
    end

    test "a store whose process is dead asks nobody rather than taking the line down with it" do
      expect(BotArmyRpg.PartyStoreMock, :get_party, fn @tenant, @user ->
        exit(:noproc)
      end)

      assert :unreadable = PartyChat.maybe_ask(@tenant, @user, @session, @line)
    end

    test "an ask the bus would not take leaves no note, because nobody was asked" do
      expect_party([@narrator])

      # A stub, not an expectation: this test is about the note *not* being written, and a
      # note that was written anyway would be seen by the `refute_received` below.
      stub(BotArmyRpg.SceneFactStoreMock, :append, fn note ->
        send(self(), {:noted, note})
        {:ok, note}
      end)

      Application.put_env(:bot_army_rpg, :nats_publisher, FailingPublisher)

      assert {:error, :no_connection_manager} =
               PartyChat.maybe_ask(@tenant, @user, @session, @line)

      refute_received {:noted, _}
    end

    test "a line that names no window is not asked about" do
      # No party read at all: there is not enough of an ask to make.
      assert :no_window = PartyChat.maybe_ask(@tenant, @user, nil, @line)
      assert :no_window = PartyChat.maybe_ask(@tenant, @user, "", @line)
      assert :no_window = PartyChat.maybe_ask(@tenant, @user, 42, @line)
    end

    test "a fact that is not a line never reaches the party" do
      note = %{"content" => "[narration_asked] companion_bot", "source" => "system"}
      gm = %{"content" => "The hall falls quiet", "source" => "gm"}

      assert :not_a_turn = PartyChat.maybe_ask(@tenant, @user, @session, note)
      assert :not_a_turn = PartyChat.maybe_ask(@tenant, @user, @session, gm)
    end
  end
end
