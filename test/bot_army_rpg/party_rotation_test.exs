defmodule BotArmyRpg.PartyRotationTest do
  @moduledoc """
  Whose turn it is to answer a line in the window's chat.

  The rule is pure — a pool drawn from a reading of the window's own notes — so it is pinned
  here rather than through the ask. Two things are worth pinning, and they are different:
  *which* members may be drawn (the fairness, a fact about the notes), and *that* the draw
  comes from that pool (the randomness, which is why a tie is asserted as a set rather than
  as a member).
  """

  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.PartyRotation

  defp table(bot_ids) do
    Enum.map(bot_ids, fn bot_id ->
      %{"character_id" => "c-#{bot_id}", "bot_id" => bot_id}
    end)
  end

  defp asked(bot_id) do
    %{
      "content" => "[narration_asked] chat #{bot_id}",
      "category" => "narration_asked",
      "source" => "system"
    }
  end

  defp drawn(pool), do: pool |> Enum.map(& &1["bot_id"]) |> Enum.sort()

  describe "least_recently_asked/2" do
    test "everyone the chat has never asked stands ahead of everyone it has" do
      members = table(~w(arda bram cira))

      assert drawn(PartyRotation.least_recently_asked(members, [asked("arda")])) ==
               ~w(bram cira)
    end

    test "a member is placed by the newest ask, so being asked last stands behind being asked in between" do
      # `arda` was asked at the start and again at the end, so they were asked last — behind
      # `bram`, who was asked only in between. A round *counted* rather than *placed* would
      # send this back to `arda`.
      members = table(~w(arda bram))

      facts = [asked("arda"), asked("bram"), asked("arda")]

      assert drawn(PartyRotation.least_recently_asked(members, facts)) == ~w(bram)
    end

    test "a member no note names is at the front of the round" do
      assert drawn(PartyRotation.least_recently_asked(table(~w(arda)), [])) == ~w(arda)
    end

    test "a turn's ask does not move the chat's round" do
      # The table resolved a turn in between. Reading that note as a chat ask would put the
      # narrator at the back of a round they were never in.
      turn = %{"content" => "[narration_asked] turn arda", "category" => "narration_asked"}
      members = table(~w(arda bram))

      assert drawn(PartyRotation.least_recently_asked(members, [turn])) == ~w(arda bram)
    end

    test "a note written before the kind was recorded moves no chat round either" do
      # `asked_kind/1` reads a kindless note as a turn. The most such a note can do is start
      # the round a member early — the lane it belongs to is not one this reads.
      older = %{"content" => "[narration_asked] arda", "category" => "narration_asked"}
      members = table(~w(arda bram))

      assert drawn(PartyRotation.least_recently_asked(members, [older])) == ~w(arda bram)
    end

    test "a note naming nobody at this table places nobody" do
      members = table(~w(arda bram))

      assert drawn(PartyRotation.least_recently_asked(members, [asked("departed")])) ==
               ~w(arda bram)
    end

    test "a window with nobody in it has no pool to draw from" do
      assert PartyRotation.least_recently_asked([], [asked("arda")]) == []
    end
  end

  describe "pick/3" do
    test "the first line of a conversation goes to somebody at the table" do
      members = table(~w(arda bram cira))

      assert {:ok, %{"bot_id" => bot_id}} = PartyRotation.pick(members, [])
      assert bot_id in ~w(arda bram cira)
    end

    test "a member the chat has never asked is drawn before one it has" do
      members = table(~w(arda bram))

      assert {:ok, %{"bot_id" => "bram"}} = PartyRotation.pick(members, [asked("arda")])
    end

    test "members tied at the front are drawn from at random, not in order" do
      # Not a claim about any one draw: the pool is three, and over enough draws every member
      # of it is reachable. A round that always named the first is not a table.
      members = table(~w(arda bram cira))

      drawn_members = for _ <- 1..80, do: elem(PartyRotation.pick(members, []), 1)["bot_id"]

      assert MapSet.new(drawn_members) == MapSet.new(~w(arda bram cira))
    end

    test "the line's own author is walked past" do
      members = table(~w(arda bram cira))

      assert {:ok, %{"bot_id" => bot_id}} = PartyRotation.pick(members, [], skip: "arda")
      assert bot_id in ~w(bram cira)
    end

    test "a member the author merely stands ahead of in the round still answers" do
      # `arda` wrote the line. Dropping the author from the pool *after* choosing would leave
      # nothing to draw and hand the line back to nobody; dropping them from the round before
      # it draws `bram`.
      members = table(~w(arda bram))

      assert {:ok, %{"bot_id" => "bram"}} =
               PartyRotation.pick(members, [asked("bram")], skip: "arda")
    end

    test "a table where everyone is the author has nobody left to ask" do
      assert :none = PartyRotation.pick(table(~w(arda)), [], skip: "arda")
      assert :none = PartyRotation.pick(table(~w(arda)), [asked("arda")], skip: "arda")
    end

    test "a window with nobody in it has no turn to take" do
      assert :none = PartyRotation.pick([], [])
      assert :none = PartyRotation.pick([], [], skip: "arda")
    end
  end
end
