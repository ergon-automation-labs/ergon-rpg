defmodule BotArmyRpg.PartyRotation do
  @moduledoc """
  Whose turn it is to answer a line in the window's chat.

  A conversation answered in the same fixed order is a queue with voices, and a conversation
  answered by whoever the dice name is a table. So a chat line goes to a member drawn at
  random from the ones the chat has asked *least recently*: everybody speaks before anybody
  speaks twice, and nobody is the voice the window always hears first.

  ## The round lives in the window

  The record is not a number rpg keeps. It is the window's own history: the `"chat"` ask
  notes name whom the chat has already asked, and a member's place in the round is the
  position of the newest note that names them (`PartyNarration.asked_of/1`). Two
  consequences, both wanted:

    * a restart, a redeploy or a second rpg never lose the round — the notes are in the
      window and the window is in the database;
    * a *turn* ask cannot move it. Turn asks leave their own notes (kind `"turn"`), and the
      round is read off the chat ones only: without that, a table resolving turns between
      chat lines would keep resetting the round to whoever follows the narrator.

  ## The one member the round walks past

  A member's own line is theirs already, so asking them to answer it is the loop `PartyChat`
  refuses. The author is dropped from the pool before the draw — so only a pool in which
  every member is the author draws nothing, which is a table of one talking to itself.
  """

  alias BotArmyRpg.PartyNarration

  @doc """
  The members the chat has asked least recently, in no particular order.

  Pure, because a member's place in the round is a reading of the notes rather than a read of
  anything: whoever has never been asked stands ahead of whoever was asked longest ago,
  which stands ahead of whoever was asked last. `pick/3` draws from this pool; this is the
  pool itself, so the fairness can be stated without depending on the draw.
  """
  def least_recently_asked(members, facts) when is_list(members) and is_list(facts) do
    placed = Enum.map(members, &{&1, placement(&1, facts)})
    front = placed |> Enum.map(&elem(&1, 1)) |> Enum.min(fn -> nil end)

    for {member, at} <- placed, at == front, do: member
  end

  @doc """
  Draw one member to answer, from the members the chat has asked least recently.

  `:skip` names the line's author, who is walked past: a member is never asked to answer
  their own words. `{:ok, member}` is who answers, and `:none` is a pool in which every
  member is the one to skip.

  The draw is random, so two windows reading the same notes may name different members —
  that is the point of it. Which members *may* be named is not random; that is
  `least_recently_asked/2`.
  """
  def pick(members, facts, opts \\ []) do
    skip = Keyword.get(opts, :skip)

    # The author is dropped before the round is read, not filtered out of it: a pool emptied
    # because its only member wrote the line is `:none`, but a member the author is merely
    # ahead of is still in the round and still answers.
    case Enum.reject(members, &(&1["bot_id"] == skip)) do
      [] -> :none
      round -> {:ok, round |> least_recently_asked(facts) |> Enum.random()}
    end
  end

  # Where a member stands in the round: the position of the newest `"chat"` note naming them,
  # or `-1` for a member no note has ever asked. Not a count of asks — the round is about how
  # long a member has been quiet, so a member asked twice early is not owed a turn before one
  # asked once late. A never-asked member is `-1` rather than `nil` because `nil` is an atom
  # and so sorts *after* every integer a note can name.
  defp placement(member, facts) do
    case asked_at(member, facts) do
      nil -> -1
      index -> index
    end
  end

  defp asked_at(member, facts) do
    facts
    |> Enum.with_index()
    |> Enum.filter(&asked?(&1, member))
    |> case do
      [] -> nil
      asked -> asked |> List.last() |> elem(1)
    end
  end

  defp asked?({fact, _index}, member) do
    PartyNarration.asked?(fact) and
      PartyNarration.asked_kind(fact) == PartyNarration.chat_kind() and
      PartyNarration.asked_of(fact) == member["bot_id"]
  end
end
