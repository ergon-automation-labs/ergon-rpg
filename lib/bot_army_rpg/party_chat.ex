defmodule BotArmyRpg.PartyChat do
  @moduledoc """
  Answering a line in the party's window.

  A window's chat is scene facts (`rpg.scene.fact.add`). Until recently only a *resolved
  turn* asked anyone to speak (`GMHandler` -> `PartyNarration.ask/4`): a line typed into the
  window resolved no action, so it asked nobody, and the window was one-way — her lines sat
  there and no member was ever handed one. This is the other caller of the same ask: when a
  line lands in a window, it is handed to one member of that table.

  Nothing about the surface changes. The window already knows how to read an ask that has no
  words yet (the `"narration"` field of `rpg.session.gather_context`, built from the note
  `PartyNarration.publish/4` leaves), so the same pending line and the same answered line
  that a turn produces are what a chat ask produces.

  ## Who answers, and who does not

  A turn is the narrator's, so a turn's ask goes to the party's narrator. A chat line is not
  a narration, so it goes round the table instead: a member drawn at random from the ones the
  chat has asked least recently answers (`PartyRotation`, whose record is the window's own
  notes). No single member is the only voice in the conversation, and no line goes unanswered
  because the narrator happens to be the one who wrote it.

  ## One ask at a time, per member

  Asking is cheap; answering is not. A model sits behind each member, and the queue it draws
  from is finite, so a window that asks five times while nobody has answered is a window
  asking for silence it will not get. A member who has been asked and has not answered is
  therefore not asked again — they hold the floor until their words land. When that leaves
  nobody to ask, the ask is `:held` and the line waits.

  The hold is per member rather than per window on purpose. It is bounded by the table (two
  companions mean at most two asks in flight, not two hundred), and it cannot wedge the
  whole window: a member whose bot is dead goes quiet without silencing the rest. When a
  member's answer lands this runs again on their words, and that is what releases the hold
  and asks the line that was waiting.

  ## The table is not allowed to talk to itself

  Answering a line is itself a line, and a line is worth an answer — so with no bound, two
  members would answer each other forever. `@banter_turns` is that bound: after a person
  speaks, at most that many member lines may follow before the table goes quiet and waits
  for someone who is actually there (`:capped`). Companions bantering is the point; a window
  that never comes back to the person in it is a model burning turns nobody reads.

  The table is the *window's* members — a session's `character_ids`, which is who the screen
  put in the scene. A party member who was never put in this window is not at this table,
  and handing them a line would put words in the mouth of someone the window does not show.
  A window with nobody in it therefore answers nobody (`:no_members`): the line is stored
  and read back, and who to put in the window is the screen's answer, not rpg's.

  Four facts are not a line the table owes an answer to, each for its own reason:

    * a note the machinery wrote — `SceneFactStore.story?/1` is the one place that decides
      what is story, and bookkeeping is not something anybody said. The rule does not lean on
      the note's signature for this: `asked?/1` reads it off the category, so a note is not a
      line however it was signed, and a member is never asked to answer rpg's own bookkeeping;
    * the GM's own prose (`"source" => "gm"`) — rpg narrating is rpg's answer already, and
      asking a member to narrate the GM's narration would be a second answer to the same
      turn; this is the fallback a turn takes when its own ask could not be published;
    * the member's own words — a line is already its author's answer, and asking them to
      answer it is the loop. The author is dropped from the round before it is read, and
      only a table where *everyone* is the author answers `:own_words`;
    * a blank line: an empty turn is not something to answer.

  ## The ask cannot fail the line

  The line is already stored and the caller is being told so by the time this runs. An ask
  that did not go out is a member nobody asked — the window says their words are not there
  yet, which is true — and never a lost turn. So every way this can end is reported by its
  kind and logged, and `handle_add/1`'s reply never changes because of it (the same
  discipline `touch_window/2` follows for the window's clock).
  """

  require Logger

  alias BotArmyRpg.{PartyNarration, PartyRead, PartyRotation, SceneFactStore}

  # rpg's own voice in the window: the fact `GMHandler` writes when there is no narrator to
  # ask, and the fact it writes instead when an ask could not be published. The window draws
  # `source` as the speaker, so this literal is also what a reader sees as the name on that
  # prose.
  @gm_source "gm"

  # How many member lines the table may write before it is talking only to itself. Two: a
  # pair of companions answering each other is a conversation, and four in a row is a window
  # that never comes back to the person in it and a model asked for turns nobody is reading.
  @banter_turns 2

  @doc """
  Hand this line to the member whose turn it is, and say what happened.

  `session_id` names the window the line landed in and must be a binary — an ask that cannot
  say which window it is for is no ask. The window is also the whole of what decides who
  answers: its members, and its own record of whom the chat asked last.

  Answers: `{:asked, member}` the member was handed the line; `:no_members` nobody is in the
  window to ask; `:own_words` the line is every member's already; `:not_a_turn` the fact is
  not something anybody said; `:no_window` the line names no window; `:held` every member the
  line could go to is still answering something else, so the line waits rather than piling a
  second ask on the model behind them; `:capped` the table has been answering itself long
  enough and is waiting for a person; `:unreadable` the window or its history could not be
  read, so nobody was asked; `{:error, reason}` the ask could not be published.
  """
  def maybe_ask(tenant_id, session_id, fact) do
    cond do
      not names_a_window?(session_id) -> :no_window
      not askable?(fact) -> :not_a_turn
      true -> ask_the_table(tenant_id, session_id, fact)
    end
  end

  # A window is named by a non-empty binary, and an empty one names nothing: an ask whose
  # window is `""` could not be answered anywhere, so it is not made.
  defp names_a_window?(session_id), do: is_binary(session_id) and session_id != ""

  @doc """
  Is this scene fact a line the table owes an answer to?

  Pure, because it is a rule about facts rather than a read of anything: what counts as
  story is `SceneFactStore.story?/1`'s answer (so a note the machinery wrote is not a
  line), the GM's own prose is not a line, and nothing said is not a line.
  """
  def askable?(fact) when is_map(fact) do
    content = fact["content"]

    not PartyNarration.asked?(fact) and fact["source"] != @gm_source and is_binary(content) and
      String.trim(content) != "" and SceneFactStore.story?(fact)
  end

  def askable?(_fact), do: false

  defp ask_the_table(tenant_id, session_id, fact) do
    case read_the_table(tenant_id, session_id) do
      {:ok, [], _facts} -> :no_members
      {:ok, members, facts} -> ask_the_round(members, facts, tenant_id, session_id, fact)
      {:error, reason} -> unread(reason)
    end
  end

  # Both of this module's reads, and the only place a dead store can take the line down with
  # it: the window's members, and the window's own history — which holds the round, the floor,
  # and the count of how long the table has been talking to itself. A window that cannot be
  # read is not a window with nobody in it: the refusal is `:unreadable`, and the failure is
  # visible by its kind, never by the arguments a dead call carries (N+64).
  defp read_the_table(tenant_id, session_id) do
    with {:ok, members} <- window_members(tenant_id, session_id),
         {:ok, facts} <- window_history(members, tenant_id, session_id) do
      {:ok, members, facts}
    end
  rescue
    _ -> {:error, :raised}
  catch
    :exit, _ -> {:error, :down}
  end

  # Nobody at this table has any turn, so there is no round to read a cursor for.
  defp window_history([], _tenant_id, _session_id), do: {:ok, []}

  defp window_history(_members, tenant_id, session_id) do
    case scene_fact_store().list_for_session(tenant_id, session_id) do
      {:ok, facts} when is_list(facts) -> {:ok, facts}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :bad_history}
    end
  end

  defp window_members(tenant_id, session_id) do
    case session_store().get(tenant_id, session_id) do
      {:ok, session} when is_map(session) -> {:ok, members_of(session)}
      {:ok, _other} -> {:error, :bad_session}
      {:error, reason} -> {:error, reason}
    end
  end

  # The window's members. Ordered by character id rather than by how the map happened to come
  # back, so that the same window reads the same list every time: who answers does not depend
  # on the order (it is a placement and a draw), but a read that is reproducible is one worth
  # logging. A character whose `bot_id` is not a name at all is not somebody the table can ask
  # and is left out.
  defp members_of(session) do
    case session["character_ids"] do
      ids when is_map(ids) ->
        ids
        |> Enum.map(fn {character_id, bot_id} ->
          %{"character_id" => character_id, "bot_id" => bot_id}
        end)
        |> Enum.filter(&is_binary(&1["bot_id"]))
        |> Enum.sort_by(& &1["character_id"])

      _other ->
        []
    end
  end

  defp ask_the_round(members, facts, tenant_id, session_id, fact) do
    # The line this ask is *about* is not always the fact that woke it: a member's own answer
    # wakes this too, and the line the table still owes is then a person's, written while the
    # member who just spoke was holding the floor.
    line = owed_line(facts, members) || newest_line(facts) || fact
    free = Enum.reject(members, &still_to_speak?(&1, facts))

    cond do
      free == [] -> :held
      banter_full?(facts, members) -> :capped
      true -> draw(free, facts, tenant_id, session_id, line)
    end
  end

  defp draw(free, facts, tenant_id, session_id, line) do
    case PartyRotation.pick(free, facts, skip: line["source"]) do
      {:ok, member} -> ask(member, tenant_id, session_id, line)
      :none -> :own_words
    end
  end

  defp ask(member, tenant_id, session_id, line) do
    case PartyNarration.ask_chat(member, session_id, tenant_id, line) do
      :ok -> {:asked, member}
      {:error, reason} -> {:error, reason}
    end
  end

  # The newest line a person wrote that the table has not been asked about yet: everything a
  # person said after the newest ask. A held line lives here — and it is deliberately a
  # person's line, because handing a member another member's words is how the table starts
  # talking to itself.
  defp owed_line(facts, members) do
    people = member_ids(members)
    last_ask = last_chat_ask_index(facts) || -1

    facts
    |> Enum.drop(last_ask + 1)
    |> Enum.filter(&(askable?(&1) and not MapSet.member?(people, &1["source"])))
    |> List.last()
  end

  defp newest_line(facts), do: facts |> Enum.filter(&askable?/1) |> List.last()

  # Has this member been asked without answering? The newest note naming them is the ask, and
  # anything they wrote after it is the answer. Read per member rather than off the newest
  # note alone: a second ask does not excuse the first.
  defp still_to_speak?(member, facts) do
    case last_ask_index_for(member, facts) do
      nil -> false
      index -> not Enum.any?(Enum.drop(facts, index + 1), &(&1["source"] == member["bot_id"]))
    end
  end

  defp last_ask_index_for(member, facts) do
    facts
    |> Enum.with_index()
    |> Enum.filter(&chat_ask_of?(&1, member))
    |> List.last()
    |> case do
      nil -> nil
      {_fact, index} -> index
    end
  end

  defp last_chat_ask_index(facts) do
    facts
    |> Enum.with_index()
    |> Enum.filter(fn {fact, _index} -> chat_ask?(fact) end)
    |> List.last()
    |> case do
      nil -> nil
      {_fact, index} -> index
    end
  end

  defp chat_ask_of?({fact, _index}, member),
    do: chat_ask?(fact) and PartyNarration.asked_of(fact) == member["bot_id"]

  defp chat_ask?(fact) do
    PartyNarration.asked?(fact) and PartyNarration.asked_kind(fact) == PartyNarration.chat_kind()
  end

  # How long the table has been talking to itself: the member lines written since the newest
  # line a person wrote. A person's line is the one thing that resets it — which is also why
  # a person's line is never capped. It is newer than itself, so the count is zero.
  defp banter_full?(facts, members) do
    people = member_ids(members)

    count =
      facts
      |> Enum.drop(person_floor(facts, people))
      |> Enum.count(&MapSet.member?(people, &1["source"]))

    count >= @banter_turns
  end

  defp person_floor(facts, people) do
    facts
    |> Enum.with_index()
    |> Enum.filter(fn {fact, _index} ->
      askable?(fact) and not MapSet.member?(people, fact["source"])
    end)
    |> List.last()
    |> case do
      nil -> 0
      {_fact, index} -> index + 1
    end
  end

  defp member_ids(members), do: MapSet.new(members, & &1["bot_id"])

  defp unread(reason) do
    Logger.warning(
      "[PartyChat] The window's table could not be read: #{inspect(PartyRead.shape(reason))}; " <>
        "nobody was asked"
    )

    :unreadable
  end

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end
end
