defmodule BotArmyRpg.PartyNarration do
  @moduledoc """
  Asking the party's narrator to narrate a turn.

  A party may hold one member in the `narrator` role (`PartyStore.narrator/1` is the only
  answer to who narrates, and `rpg.party.set_narrator` the only thing that can change
  it). When it does, the narrated turn is hers, so rpg asks her and writes none of the
  words itself.

  The ask carries the actor, the action and its resolution because **when a narrator
  narrates, the GM writes no scene fact for that turn**: this event is then the only place
  the turn's material exists, and prose written from anything less would be invented
  rather than narrated.

  The ask is published once and never awaited. rpg cannot know whether she will answer,
  so it does not pretend she did: it writes no fact, and its reply says the narration is
  `nil` with the narrator named. What a table shows while a turn has no words yet is the
  window's own reading (see `docs/PARTY.md`, "Whose name is on the words").

  ## The note the ask leaves

  An ask is also written down, as a note on the window itself. The note is not words and
  never becomes story: it is signed `"system"`, so `SceneFactStore.story?/1` leaves it out
  of the carry and the window's own read leaves it out of its turns. What it is for is the
  *pending* reading a table needs: while the newest thing in a window is a note asking her
  for this turn, her words have not arrived, and the table can say that instead of showing
  a turn with nothing in it (the `"narration"` field of `rpg.session.gather_context`).

  ## The chat ask

  A window's chat is the same window: a line someone types into it is a scene fact like any
  other, and a conversation in which nobody ever answers is not a conversation. `ask_chat/4`
  is the same ask for a line rather than a resolved turn — the one subject, the same pending
  reading — and `"kind"` is what tells the two apart at the far end, because the words a
  member is asked for are not the same words in both cases: a turn wants prose about an
  action and its resolution, a chat line wants an answer to what somebody said.

  A turn's ask is `"kind" => "turn"`; a chat's is `"kind" => "chat"` and carries the line
  and who said it. The field was added after the ask subject, so a reader that finds no
  kind at all is reading an older rpg and should treat it as a turn.

  Who a chat line is handed to is not this module's answer — a turn is the narrator's, but
  a chat line goes round the table (`PartyChat` picks it with `PartyRotation`) — and this
  only asks the member it is given.

  ## The note says which kind of ask it was

  The note names its kind as well as the member (`[narration_asked] chat companion_bot`),
  because the window's round is read off the *chat* notes alone (`last_asked/2`): a table
  that resolved turns between chat lines would otherwise keep resetting the round to
  whoever follows the narrator. A note written before the kind was recorded cannot say
  which lane asked; those are read as turns (`asked_kind/1`), so at worst the round starts
  one member early once.
  """

  alias BotArmyRpg.NATS.Publisher

  require Logger

  @subject "rpg.narration.your_turn"

  @kind_turn "turn"
  @kind_chat "chat"
  @kinds [@kind_turn, @kind_chat]

  # The machinery speaking is not a person in the scene: every note rpg writes is signed
  # this way, which is what keeps it out of the carry and out of the window's turns
  # (`SceneFactStore.story?/1`) while still being readable in the facts.
  @machine_source "system"

  # The note an ask leaves on the window. A note says what it is in its own first word —
  # the `[verification]` convention — so the mark is that word, and the category is the
  # same name as a field, for the reader that takes the fact apart instead of reading it.
  @asked_category "narration_asked"
  @asked_mark "[narration_asked]"

  @doc """
  Ask `member` to narrate the turn `turn` describes, in `session`.

  `turn` is `%{"actor" => character, "action" => action, "resolution" => resolution}` —
  the same three things a GM narration is built from, so a narrator is asked with exactly
  what the GM would have had.

  The publisher is read from the application environment at call time so a test can hold
  the ask instead of sending it (the same seam `GM.Narrator` uses to reach NATS).
  """
  def ask(member, session, tenant_id, turn) do
    publish(payload(member, session, turn), session["id"], tenant_id, @kind_turn)
  end

  @doc """
  Ask `member` to answer the line `fact` someone wrote in the window `session_id`.

  The same subject, the same note and the same pending reading as a turn's ask; what
  differs is the material (`chat_payload/3`). Published once and never awaited: rpg cannot
  know whether she answers, so the window says her words are not there yet rather than
  putting any in her mouth.
  """
  def ask_chat(member, session_id, tenant_id, fact) do
    publish(chat_payload(member, session_id, fact), session_id, tenant_id, @kind_chat)
  end

  # The ask and the note are one act: an ask that left no note would be an ask a table
  # cannot see, so it is this module's business and never a caller's. Nothing publishes
  # without a note, and a bus that would not take the ask writes none, because nobody was
  # asked.
  defp publish(event, session_id, tenant_id, kind) do
    case publisher().publish(@subject, event, tenant_id: tenant_id) do
      :ok ->
        note_the_ask(%{"bot_id" => event["bot_id"]}, session_id, tenant_id, kind)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The event a narrator receives for a chat line.

  `bot_id` and `character_id` are hers, as in a turn's ask, so a bot answers to the name it
  is configured with and ignores every other party's asks. The rest is the line: `content`
  is what was said, `speaker` is who said it (the window draws `source` as the speaker), and
  `session_id` names the window she is to answer in — the log itself she reads from the
  window, so rpg does not send it.
  """
  def chat_payload(member, session_id, fact) do
    %{
      "kind" => @kind_chat,
      "session_id" => session_id,
      "character_id" => member["character_id"],
      "bot_id" => member["bot_id"],
      "content" => fact["content"],
      "speaker" => fact["source"]
    }
  end

  @doc """
  Write down that `member` was asked, on the window itself.

  One owner for the note, and in practice the ask writes it (`publish/4`), because the ask
  and the note are one act: an ask that left no note would be an ask a table cannot see,
  and both lanes (a resolved turn and a chat line) owe the same note for the same pending
  reading. Public because a caller that asked by some other road still owes it.

  Best effort, and reported by its kind: the ask is already published, and a note that was
  not written costs the table its pending reading rather than costing anyone a turn.
  """
  def note_the_ask(member, session_id, tenant_id, kind \\ @kind_turn) do
    case scene_fact_store().append(%{
           "session_id" => session_id,
           "tenant_id" => tenant_id,
           "content" => note_content(member, kind),
           "category" => @asked_category,
           "source" => @machine_source
         }) do
      {:ok, _note} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[PartyNarration] The note for #{member["bot_id"]} was not written: #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc """
  The event a narrator receives.

  `bot_id` and `character_id` are hers — the member the party names — so a bot that
  subscribes can answer to the name it is configured with and ignore every other party's
  turns. Pure, so the shape an answer is written against is pinned by a test rather than
  by reading the code that writes it.
  """
  def payload(member, session, turn) do
    %{
      "kind" => @kind_turn,
      "session_id" => session["id"],
      "character_id" => member["character_id"],
      "bot_id" => member["bot_id"],
      "scene_description" => session["scene_description"],
      "round" => turn_round(session),
      "actor" => turn["actor"],
      "action" => turn["action"],
      "resolution" => turn["resolution"]
    }
  end

  @doc "The subject the ask is published on."
  def subject, do: @subject

  @doc "The category of the note an ask leaves on the window."
  def asked_category, do: @asked_category

  @doc "The kind a chat ask is made in."
  def chat_kind, do: @kind_chat

  @doc "The kind a turn ask is made in."
  def turn_kind, do: @kind_turn

  @doc """
  Is this scene fact the note an ask left?

  Read off the category, not off the content: this is the ask's own bookkeeping, and a
  prose turn that happened to open with the mark is not a note.
  """
  def asked?(fact), do: fact["category"] == @asked_category

  @doc """
  The content of the note that records asking `member`.

  The window reads its turns off `content`, so the note says what kind of ask it was and
  whom it asked behind the mark: a note that only said "asked" would not say who was
  asked, and one that did not say the kind would let a turn's ask move the chat's round.
  """
  def note_content(member, kind \\ @kind_turn),
    do: "#{@asked_mark} #{kind} #{member["bot_id"]}"

  @doc """
  Who a note asked, read back out of it.

  The inverse of `note_content/2`, and nothing else: `nil` for a fact that is not a note's
  content, and `nil` for a note that names nobody. A note with no kind in it is a note an
  older rpg wrote, and its whole remainder is the member it names.
  """
  def asked_of(fact) do
    case named_in(fact) do
      nil -> nil
      rest -> rest |> drop_kind() |> blank_to_nil()
    end
  end

  @doc """
  Which lane a note's ask was made in: `"turn"`, `"chat"`, or `nil` for a fact that is not
  a note.

  A note an older rpg wrote carries no kind and is read as a turn: the chat lane only
  existed after this field, and no reader can tell a chat ask from a turn ask in a note
  that does not say.
  """
  def asked_kind(fact) do
    case named_in(fact) do
      nil -> nil
      rest -> rest |> split_kind() |> elem(0)
    end
  end

  @doc """
  The member the newest note of this `kind` names, or `nil`.

  `facts` is a window's facts in the order they were written (`SceneFactStore`'s own
  order), so the newest is the last one that matches. This is the chat's round: whom the
  chat asked last (`PartyRotation`).
  """
  def last_asked(facts, kind) when is_list(facts) do
    facts
    |> Enum.filter(&(asked?(&1) and asked_kind(&1) == kind))
    |> List.last()
    |> case do
      nil -> nil
      note -> asked_of(note)
    end
  end

  def last_asked(_facts, _kind), do: nil

  # What follows the mark, trimmed; `nil` for a fact that is not a note at all. A *note* is
  # the category's answer (`asked?/1`), so prose that merely opens with the mark is nobody's
  # note and names nobody — the two readers below are only ever asked about notes.
  defp named_in(fact) do
    content = fact["content"]

    if asked?(fact) and is_binary(content) and
         String.starts_with?(String.trim_leading(content), @asked_mark) do
      content
      |> String.trim_leading()
      |> String.replace_prefix(@asked_mark, "")
      |> String.trim()
    end
  end

  # `[narration_asked] <kind> <bot_id>` — and, for a note written before the kind was
  # recorded, `[narration_asked] <bot_id>`. A member named `turn` or `chat` alone has no
  # kind before it, so it is read as the member rather than as a kind with nobody after it.
  defp split_kind(rest) do
    case String.split(rest, " ", parts: 2) do
      [kind, name] when kind in @kinds and name != "" -> {kind, name}
      _other -> {@kind_turn, rest}
    end
  end

  defp drop_kind(rest), do: rest |> split_kind() |> elem(1) |> String.trim()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(bot_id), do: bot_id

  defp turn_round(session), do: get_in(session, ["metadata", "turn_state", "round"])

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  defp publisher, do: Application.get_env(:bot_army_rpg, :nats_publisher, Publisher)
end
