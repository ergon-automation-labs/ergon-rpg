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
  """

  alias BotArmyRpg.NATS.Publisher

  @subject "rpg.narration.your_turn"

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
  The event a narrator receives.

  `bot_id` and `character_id` are hers — the member the party names — so a bot that
  subscribes can answer to the name it is configured with and ignore every other party's
  turns. Pure, so the shape an answer is written against is pinned by a test rather than
  by reading the code that writes it.
  """
  def payload(member, session, turn) do
    %{
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

  defp turn_round(session), do: get_in(session, ["metadata", "turn_state", "round"])

  defp publisher, do: Application.get_env(:bot_army_rpg, :nats_publisher, Publisher)
end
