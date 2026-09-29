defmodule BotArmyRpg.SceneFactStoreTest do
  use ExUnit.Case
  @moduletag :stores

  alias BotArmyRpg.SceneFactStore

  describe "story?/1" do
    test "a turn someone in the scene spoke is story" do
      assert SceneFactStore.story?(%{"source" => "operator", "content" => "Hi!"})
      assert SceneFactStore.story?(%{"source" => "gm", "content" => "the GM closed the door"})
    end

    test "the machinery speaking is not story, whatever it says" do
      refute SceneFactStore.story?(%{"source" => "system", "content" => "the day advanced"})
    end

    test "a note that declares itself a check is not story, whoever wrote it" do
      refute SceneFactStore.story?(%{
               "source" => "operator",
               "content" => "[verification] M1: a turn moves the window clock"
             })
    end

    test "a note is recognised through leading whitespace and shouting" do
      refute SceneFactStore.story?(%{"source" => "gm", "content" => "  [verification] x"})
      refute SceneFactStore.story?(%{"source" => "gm", "content" => "[VERIFICATION] x"})
    end

    test "the word elsewhere in a turn does not make the turn a note" do
      assert SceneFactStore.story?(%{
               "source" => "operator",
               "content" => "my [verification] came back green"
             })
    end

    test "a fact without a content is not a note" do
      assert SceneFactStore.story?(%{"source" => "gm"})
    end
  end

  describe "select_recent/3" do
    @tenant "00000000-0000-0000-0000-000000000099"
    @user "00000000-0000-0000-0000-0000000000aa"
    @here "00000000-0000-0000-0000-0000000000cc"
    @earlier "00000000-0000-0000-0000-0000000000bb"

    defp fact(content, source, at, session \\ @earlier) do
      %{
        "content" => content,
        "source" => source,
        "session_id" => session,
        "tenant_id" => @tenant,
        "user_id" => @user,
        "created_at" => at
      }
    end

    # The newest two facts are notes, so a selection that filtered *after* the
    # limit would answer one turn and one note-or-nothing; the newest two *turns*
    # are what a caller asked for.
    defp facts_with_newest_two_notes do
      [
        fact("the oldest turn", "operator", "2026-05-10T09:00:00"),
        fact("[verification] the middle note", "system", "2026-05-10T10:00:00"),
        fact("a turn from yesterday", "gm", "2026-05-10T11:00:00"),
        fact("[verification] the newest note", "operator", "2026-05-10T12:00:00")
      ]
    end

    test "answers newest first, this identity's, without this window's own turns" do
      facts =
        facts_with_newest_two_notes() ++
          [fact("this window's own turn", "operator", "2026-05-10T13:00:00", @here)] ++
          [
            %{
              fact("another household's turn", "operator", "2026-05-10T14:00:00")
              | "user_id" => "someone-else"
            }
          ]

      selected =
        SceneFactStore.select_recent(facts, @tenant,
          exclude_session_id: @here,
          user_id: @user,
          limit: 10
        )

      assert Enum.map(selected, & &1["content"]) == [
               "[verification] the newest note",
               "a turn from yesterday",
               "[verification] the middle note",
               "the oldest turn"
             ]
    end

    test "story_only drops every note" do
      selected =
        SceneFactStore.select_recent(facts_with_newest_two_notes(), @tenant,
          user_id: @user,
          story_only: true,
          limit: 10
        )

      assert Enum.map(selected, & &1["content"]) == [
               "a turn from yesterday",
               "the oldest turn"
             ]
    end

    test "story_only drops the notes before the limit, so the limit counts turns" do
      selected =
        SceneFactStore.select_recent(facts_with_newest_two_notes(), @tenant,
          user_id: @user,
          story_only: true,
          limit: 2
        )

      assert Enum.map(selected, & &1["content"]) == [
               "a turn from yesterday",
               "the oldest turn"
             ]
    end

    test "a window whose newest facts are all notes carries nothing, not a note" do
      facts = [
        fact("[verification] one", "system", "2026-05-10T11:00:00"),
        fact("[verification] two", "operator", "2026-05-10T12:00:00")
      ]

      assert SceneFactStore.select_recent(facts, @tenant, user_id: @user, story_only: true) == []
    end
  end
end
