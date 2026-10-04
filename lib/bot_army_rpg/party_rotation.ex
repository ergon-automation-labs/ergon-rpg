defmodule BotArmyRpg.PartyRotation do
  @moduledoc """
  Whose turn it is to answer a line in the window's chat.

  A conversation answered by the same member every time is a monologue with two voices. The
  *turn* lane asks the party's narrator, because a narrated turn is hers; a *chat line* is
  not a narration, so it goes round the table: the member after the one the chat asked last
  answers, and so on.

  ## The round lives in the window

  The cursor is not a number rpg keeps. It is the window's own history: the newest
  `"narration_asked"` note of kind `"chat"` names whom the chat asked last
  (`PartyNarration.last_asked/2`), and the next member in the window's order is next. Two
  consequences, both wanted:

    * a restart, a redeploy or a second rpg never lose the round — the notes are in the
      window and the window is in the database;
    * a *turn* ask cannot move it. Turn asks leave their own notes (kind `"turn"`), and the
      round is read off the chat ones only: without that, a table resolving turns between
      chat lines would keep resetting the round to whoever follows the narrator.

  ## The order

  The round is over the window's members — a session's `character_ids` — ordered by
  character id, so the same window always reads the same round. They are the people in the
  scene: a party member who has not been put in this window is not at this table, and asking
  them would put words in the mouth of someone the window does not show.

  ## The one member the round walks past

  A member's own line is theirs already, so asking them to answer it is the loop `PartyChat`
  refuses. The round skips the line's author — and only answers `:none` when *every* member
  of the round is the author, which is a table of one talking to itself.
  """

  @doc """
  The member after `last` (or the first member, when `last` names nobody in the round).

  `:skip` names the line's author, who is walked past: a member is never asked to answer
  their own words. `{:ok, member}` is who answers, and `:none` is a round in which every
  member is the one to skip.

  Pure, because the order of the round is a rule about a list rather than a read of
  anything: what the round is over — the window's members, ordered — is the caller's
  answer, and this only says whose turn it is.
  """
  def pick(members, last, opts \\ [])

  def pick([], _last, _opts), do: :none

  def pick(members, last, opts) do
    skip = Keyword.get(opts, :skip)
    size = length(members)
    start = start_index(members, last)

    Enum.reduce_while(0..(size - 1), :none, fn step, _none ->
      member = Enum.at(members, rem(start + step, size))

      if member["bot_id"] == skip do
        {:cont, :none}
      else
        {:halt, {:ok, member}}
      end
    end)
  end

  # The round continues *after* the member the chat asked last. A last ask that names
  # nobody in this round — a member who has since left the window — is not a position in
  # it, so the round starts over rather than picking an arbitrary successor.
  defp start_index(members, last) do
    case index_of(members, last) do
      nil -> 0
      index -> index + 1
    end
  end

  defp index_of(_members, last) when not is_binary(last), do: nil

  defp index_of(members, last), do: Enum.find_index(members, &(&1["bot_id"] == last))
end
