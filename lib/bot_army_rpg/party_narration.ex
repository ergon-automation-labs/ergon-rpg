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

  A window's chat is the same window and the same narrator: a line someone types into it
  is a scene fact like any other, and a conversation in which nobody ever answers is not a
  conversation. `ask_chat/4` is the same ask for a line rather than a resolved turn — the
  one subject, the same pending reading — and `"kind"` is what tells the two apart at the
  far end, because the words a narrator is asked for are not the same words in both cases:
  a turn wants prose about an action and its resolution, a chat line wants an answer to
  what somebody said.

  A turn's ask is `"kind" => "turn"`; a chat's is `"kind" => "chat"` and carries the line
  and who said it. The field was added after the ask subject, so a reader that finds no
  kind at all is reading an older rpg and should treat it as a turn.
  """

  alias BotArmyRpg.NATS.Publisher

  require Logger

  @subject "rpg.narration.your_turn"

  @kind_turn "turn"
  @kind_chat "chat"

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
    publisher().publish(@subject, payload(member, session, turn), tenant_id: tenant_id)
  end

  @doc """
  Ask `member` to answer the line `fact` someone wrote in the window `session_id`.

  The same subject, the same note and the same pending reading as a turn's ask; what
  differs is the material (`chat_payload/3`). Published once and never awaited: rpg cannot
  know whether she answers, so the window says her words are not there yet rather than
  putting any in her mouth.
  """
  def ask_chat(member, session_id, tenant_id, fact) do
    publisher().publish(@subject, chat_payload(member, session_id, fact), tenant_id: tenant_id)
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

  One owner for the note, because the ask and the note are one act: an ask that left no
  note would be an ask a table cannot see, and both callers of this module (a resolved
  turn and a chat line) owe it the same note for the same pending reading.

  Best effort, and reported by its kind: the ask is already published, and a note that was
  not written costs the table its pending reading rather than costing anyone a turn.
  """
  def note_the_ask(member, session_id, tenant_id) do
    case scene_fact_store().append(%{
           "session_id" => session_id,
           "tenant_id" => tenant_id,
           "content" => note_content(member),
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

  @doc """
  Is this scene fact the note an ask left?

  Read off the category, not off the content: this is the ask's own bookkeeping, and a
  prose turn that happened to open with the mark is not a note.
  """
  def asked?(fact), do: fact["category"] == @asked_category

  @doc """
  The content of the note that records asking `member` for a turn.

  The window reads its turns off `content`, so the note says whom it asked behind the
  mark: a note that only said "asked" would not say who was asked.
  """
  def note_content(member), do: "#{@asked_mark} #{member["bot_id"]}"

  @doc """
  Who a note asked, read back out of it.

  The inverse of `note_content/1`, and nothing else: `nil` for a fact that is not a note's
  content, and `nil` for a note that names nobody.
  """
  def asked_of(fact) do
    content = fact["content"]

    if is_binary(content) and String.starts_with?(String.trim_leading(content), @asked_mark) do
      content
      |> String.trim_leading()
      |> String.replace_prefix(@asked_mark, "")
      |> String.trim()
      |> blank_to_nil()
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(bot_id), do: bot_id

  defp turn_round(session), do: get_in(session, ["metadata", "turn_state", "round"])

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  defp publisher, do: Application.get_env(:bot_army_rpg, :nats_publisher, Publisher)
end
