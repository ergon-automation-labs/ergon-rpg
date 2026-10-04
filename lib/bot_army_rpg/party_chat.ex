defmodule BotArmyRpg.PartyChat do
  @moduledoc """
  Answering a line in the party's window.

  A window's chat is scene facts (`rpg.scene.fact.add`). Until recently only a *resolved
  turn* asked anyone to speak (`GMHandler` -> `PartyNarration.ask/4`): a line typed into the
  window resolved no action, so it asked nobody, and the window was one-way — her lines sat
  there and no member was ever handed one. This is the other caller of the same ask: when a
  line lands in a window, it is handed to the member whose turn it is.

  Nothing about the surface changes. The window already knows how to read an ask that has no
  words yet (the `"narration"` field of `rpg.session.gather_context`, built from the note
  `PartyNarration.publish/4` leaves), so the same pending line and the same answered line
  that a turn produces are what a chat ask produces.

  ## Who answers, and who does not

  A turn is the narrator's, so a turn's ask goes to the party's narrator. A chat line is not
  a narration, so it goes round the table instead: the member after the one the chat asked
  last answers (`PartyRotation`, whose cursor is the window's own notes). No single member
  is the only voice in the conversation, and no line goes unanswered because the narrator
  happens to be the one who wrote it.

  The table is the *window's* members — a session's `character_ids`, which is who the screen
  put in the scene. A party member who was never put in this window is not at this table,
  and handing them a line would put words in the mouth of someone the window does not show.
  A window with nobody in it therefore answers nobody (`:no_members`): the line is stored
  and read back, and who to put in the window is the screen's answer, not rpg's.

  Four facts are not a line the table owes an answer to, each for its own reason:

    * a note the machinery wrote — `SceneFactStore.story?/1` is the one place that decides
      what is story, and bookkeeping is not something anybody said;
    * the GM's own prose (`"source" => "gm"`) — rpg narrating is rpg's answer already, and
      asking a member to narrate the GM's narration would be a second answer to the same
      turn; this is the fallback a turn takes when its own ask could not be published;
    * the member's own words — a line is already its author's answer, and asking them to
      answer it is the loop. The round walks past the author, and only a table where
      *everyone* is the author answers `:own_words`;
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

  @doc """
  Hand this line to the member whose turn it is, and say what happened.

  `session_id` names the window the line landed in and must be a binary — an ask that cannot
  say which window it is for is no ask. The window is also the whole of what decides who
  answers: its members, and its own record of whom the chat asked last.

  Answers: `{:asked, member}` the member was handed the line; `:no_members` nobody is in the
  window to ask; `:own_words` the line is every member's already; `:not_a_turn` the fact is
  not something anybody said; `:no_window` the line names no window; `:unreadable` the
  window or its history could not be read, so nobody was asked; `{:error, reason}` the ask
  could not be published.
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

    fact["source"] != @gm_source and is_binary(content) and String.trim(content) != "" and
      SceneFactStore.story?(fact)
  end

  def askable?(_fact), do: false

  defp ask_the_table(tenant_id, session_id, fact) do
    case read_the_table(tenant_id, session_id) do
      {:ok, [], _last} -> :no_members
      {:ok, members, last} -> ask_the_round(members, last, tenant_id, session_id, fact)
      {:error, reason} -> unread(reason)
    end
  end

  # Both of this module's reads, and the only place a dead store can take the line down with
  # it: the window's members, and the round's cursor out of the window's own history. A
  # window that cannot be read is not a window with nobody in it — the refusal is
  # `:unreadable`, and the failure is visible by its kind, never by the arguments a dead call
  # carries (N+64).
  defp read_the_table(tenant_id, session_id) do
    with {:ok, members} <- window_members(tenant_id, session_id),
         {:ok, last} <- last_chat_ask(members, tenant_id, session_id) do
      {:ok, members, last}
    end
  rescue
    _ -> {:error, :raised}
  catch
    :exit, _ -> {:error, :down}
  end

  # Nobody at this table has any turn, so there is no round to read a cursor for.
  defp last_chat_ask([], _tenant_id, _session_id), do: {:ok, nil}

  defp last_chat_ask(_members, tenant_id, session_id) do
    case scene_fact_store().list_for_session(tenant_id, session_id) do
      {:ok, facts} when is_list(facts) ->
        {:ok, PartyNarration.last_asked(facts, PartyNarration.chat_kind())}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :bad_history}
    end
  end

  defp window_members(tenant_id, session_id) do
    case session_store().get(tenant_id, session_id) do
      {:ok, session} when is_map(session) -> {:ok, members_of(session)}
      {:ok, _other} -> {:error, :bad_session}
      {:error, reason} -> {:error, reason}
    end
  end

  # The window's members, ordered by character id rather than by how the map happened to
  # come back: the round is a rule about a list, so the same window must read the same order
  # every time. A character whose `bot_id` is not a name at all is not somebody the table can
  # ask and is left out.
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

  defp ask_the_round(members, last, tenant_id, session_id, fact) do
    case PartyRotation.pick(members, last, skip: fact["source"]) do
      {:ok, member} ->
        case PartyNarration.ask_chat(member, session_id, tenant_id, fact) do
          :ok -> {:asked, member}
          {:error, reason} -> {:error, reason}
        end

      :none ->
        :own_words
    end
  end

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
