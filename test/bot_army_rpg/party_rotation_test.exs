defmodule BotArmyRpg.PartyRotationTest do
  @moduledoc """
  Whose turn it is to answer a line in the window's chat.

  The rule is pure — a round over a list — so it is pinned here rather than through the ask:
  the interesting cases are the ones a table runs into over a long conversation (the round
  moving on, a turn ask not moving it, and the line's own author being walked past), and
  each is an answer about a list rather than about anything a store said.
  """

  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.PartyRotation

  defp table(bot_ids) do
    Enum.map(bot_ids, fn bot_id ->
      %{"character_id" => "c-#{bot_id}", "bot_id" => bot_id}
    end)
  end

  describe "pick/3" do
    test "the first line of a conversation goes to the first member at the table" do
      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(table(~w(arda bram cira)), nil)
    end

    test "the round continues after the member the chat asked last" do
      members = table(~w(arda bram cira))

      assert {:ok, %{"bot_id" => "bram"}} = PartyRotation.pick(members, "arda")
      assert {:ok, %{"bot_id" => "cira"}} = PartyRotation.pick(members, "bram")
      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(members, "cira")
    end

    test "a last ask that names nobody at this table starts the round over" do
      # A member who left the window is not a position in it: picking their successor would
      # be picking a stranger, so the round begins again.
      members = table(~w(arda bram))

      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(members, "departed")
      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(members, 42)
      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(members, "")
    end

    test "the line's own author is walked past, and the round moves on" do
      members = table(~w(arda bram cira))

      # `arda` wrote the line, so the round hands it to the next member rather than back to
      # them; and the *cursor* then reads from `bram`, so the next line reaches `cira`.
      assert {:ok, %{"bot_id" => "bram"}} = PartyRotation.pick(members, "arda", skip: "arda")
      assert {:ok, %{"bot_id" => "cira"}} = PartyRotation.pick(members, "bram", skip: "arda")
      assert {:ok, %{"bot_id" => "bram"}} = PartyRotation.pick(members, "cira", skip: "arda")
    end

    test "a table where everyone is the author has nobody left to ask" do
      assert :none = PartyRotation.pick(table(~w(arda)), nil, skip: "arda")
      assert :none = PartyRotation.pick(table(~w(arda)), "arda", skip: "arda")
    end

    test "a window with nobody in it has no turn to take" do
      assert :none = PartyRotation.pick([], nil)
      assert :none = PartyRotation.pick([], "arda", skip: "arda")
    end

    test "with nobody to walk past, everyone is in the round" do
      members = table(~w(arda bram))

      assert {:ok, %{"bot_id" => "arda"}} = PartyRotation.pick(members, "bram")
    end
  end
end
