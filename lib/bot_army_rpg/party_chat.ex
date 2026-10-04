defmodule BotArmyRpg.PartyChat do
  @moduledoc """
  Answering her in the party's window.

  A window's chat is scene facts (`rpg.scene.fact.add`), and the durable party is what says
  who is in the scene with her. Until now only a *resolved turn* asked anyone to speak
  (`GMHandler` -> `PartyNarration.ask/4`): a line typed into the window resolved no action,
  so it asked nobody, and the window was one-way — her lines sat there and no member was
  ever handed one. This is the other caller of the same ask: when a line lands in a window
  whose party names a narrator, she is asked to answer it.

  Nothing about the surface changes. The window already knows how to read an ask that has
  no words yet (the `"narration"` field of `rpg.session.gather_context`, built from the
  note `PartyNarration.note_the_ask/3` leaves), so the same pending line and the same
  answered line that a turn produces are what a chat ask produces.

  ## Who is asked, and who is not

  The party's narrator, and nobody else. The `narrator` role is the one answer to who
  narrates (`PartyStore.narrator/1`, set by `rpg.party.set_narrator`), and a line answered
  by a member nobody handed it to would be words in another member's mouth. A party with no
  narrator is a party that answers nobody — the line is stored, read back and that is all,
  exactly as before.

  Three facts are not a line the table owes an answer to, each for its own reason:

    * a note the machinery wrote — `SceneFactStore.story?/1` is the one place that decides
      what is story, and bookkeeping is not something anybody said;
    * the GM's own prose (`"source" => "gm"`) — rpg narrating is rpg's answer already, and
      asking her to narrate the GM's narration would be a second answer to the same turn;
      this is the fallback a turn takes when its own ask could not be published;
    * the narrator's own words — those *are* the answer, and asking her again would loop.

  A blank line is not a line either: an empty turn is not something to answer.

  ## The ask cannot fail the line

  The line is already stored and the caller is being told so by the time this runs. An ask
  that did not go out is a member nobody asked — the window says her words are not there
  yet, which is true — and never a lost turn. So every way this can end is reported by its
  kind and logged, and `handle_add/1`'s reply never changes because of it (the same
  discipline `touch_window/2` follows for the window's clock).
  """

  require Logger

  alias BotArmyRpg.{PartyNarration, PartyRead, SceneFactStore}

  # rpg's own voice in the window: the fact `GMHandler` writes when there is no narrator to
  # ask, and the fact it writes instead when an ask could not be published. The window
  # draws `source` as the speaker, so this literal is also what a reader sees as the name on
  # that prose.
  @gm_source "gm"

  @doc """
  Ask the window's narrator to answer this line, and say what happened.

  `session_id` names the window the line landed in and must be a binary — an ask that
  cannot say which window it is for is no ask. `user_id` is the identity whose party this
  window's members come from (the same identity its line was written under).

  Answers: `{:asked, member}` she was handed the line; `:no_narrator` the party names none
  (or holds no party at all); `:own_words` the line is hers already; `:not_a_turn` the fact
  is not something anybody said; `:no_window` the line names no window; `:unreadable` the
  party could not be read, so nobody was asked; `{:error, reason}` the ask could not be
  published.
  """
  def maybe_ask(tenant_id, user_id, session_id, fact) do
    cond do
      not names_a_window?(session_id) -> :no_window
      not askable?(fact) -> :not_a_turn
      true -> ask_the_narrator(tenant_id, user_id, session_id, fact)
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

  defp ask_the_narrator(tenant_id, user_id, session_id, fact) do
    case PartyRead.narrator(tenant_id, user_id) do
      {:ok, nil} -> :no_narrator
      {:ok, member} -> ask_member(member, session_id, tenant_id, fact)
      {:error, reason} -> unread(reason)
    end
  rescue
    _ -> unread(:raised)
  catch
    :exit, _ -> unread(:down)
  end

  defp ask_member(member, session_id, tenant_id, fact) do
    if member["bot_id"] == fact["source"] do
      :own_words
    else
      case PartyNarration.ask_chat(member, session_id, tenant_id, fact) do
        :ok ->
          PartyNarration.note_the_ask(member, session_id, tenant_id)
          {:asked, member}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # A party that cannot be read is not a party with no narrator: nobody is asked, and the
  # failure is visible by its kind — never by the arguments a dead call carries, which are
  # the party's key (N+64).
  defp unread(reason) do
    Logger.warning(
      "[PartyChat] Party unread: #{inspect(PartyRead.shape(reason))}; nobody was asked"
    )

    :unreadable
  end
end
