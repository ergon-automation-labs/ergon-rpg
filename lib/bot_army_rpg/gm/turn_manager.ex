defmodule BotArmyRpg.GM.TurnManager do
  @moduledoc """
  Pure functions for managing turn order inside session metadata.

  Turn state lives in `session["metadata"]["turn_state"]`:
    - `turn_order`    → list of character_id strings
    - `active_index`  → integer pointing to current actor
    - `round`         → integer round counter
    - `turn_history`  → list of resolved turn records
  """

  @doc """
  Build initial turn state from a session's `character_ids` map.
  Returns a metadata fragment to merge into `session["metadata"]`.
  """
  def build_turn_state(session) do
    character_ids =
      session
      |> Map.get("character_ids", %{})
      |> Map.keys()
      |> Enum.sort()

    %{
      "turn_state" => %{
        "turn_order" => character_ids,
        "active_index" => 0,
        "round" => 1,
        "turn_history" => []
      }
    }
  end

  @doc """
  Get the current actor from session metadata.
  Returns `%{character_id: ..., bot_id: ..., type: "bot"|"player"}` or `nil`.
  """
  def current_actor(session) do
    turn_state = get_in(session, ["metadata", "turn_state"])

    if is_nil(turn_state) do
      nil
    else
      order = turn_state["turn_order"] || []
      index = turn_state["active_index"] || 0

      character_id = Enum.at(order, index)

      if is_nil(character_id) do
        nil
      else
        character_ids = session["character_ids"] || %{}
        bot_id = character_ids[character_id]

        type =
          if is_binary(bot_id) and bot_id != "" do
            "bot"
          else
            "player"
          end

        %{
          "character_id" => character_id,
          "bot_id" => bot_id,
          "type" => type
        }
      end
    end
  end

  @doc """
  Advance to the next actor. Wraps `active_index` around `turn_order`.
  Increments `round` when wrapping back to index 0.
  Returns a metadata fragment to merge.
  """
  def advance_turn(session) do
    turn_state = get_in(session, ["metadata", "turn_state"]) || %{}

    order = turn_state["turn_order"] || []
    index = turn_state["active_index"] || 0
    round = turn_state["round"] || 1

    next_index = rem(index + 1, max(length(order), 1))
    next_round = if next_index == 0, do: round + 1, else: round

    %{
      "turn_state" => %{
        turn_state
        | "active_index" => next_index,
          "round" => next_round
      }
    }
  end

  @doc """
  Build a pause snapshot from current turn state.
  Returns a metadata fragment to merge.
  """
  def pause_state(session) do
    metadata = session["metadata"] || %{}
    turn_state = metadata["turn_state"]

    if is_nil(turn_state) do
      metadata
    else
      Map.put(metadata, "turn_state", turn_state)
    end
  end

  @doc """
  Record a completed turn in turn_history.
  Returns a metadata fragment to merge.
  """
  def record_turn(session, character_id, action, outcome) do
    turn_state = get_in(session, ["metadata", "turn_state"]) || %{}

    history = turn_state["turn_history"] || []

    record = %{
      "character_id" => character_id,
      "action" => action,
      "outcome" => outcome,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "turn_state" => %{turn_state | "turn_history" => [record | history]}
    }
  end
end
