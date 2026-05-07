defmodule BotArmyRpg.GM.ActionResolver do
  @moduledoc """
  Orchestrates full action adjudication:

  parse action → build dice notation → roll → resolve outcome → compute stat deltas
  """

  alias BotArmyRpg.GM.{RulesEngine, Dice}

  @doc """
  Resolve an action for a character under a theme.

  Returns `{:ok, %{"rolls" => [...], "total" => int, "outcome" => string,
                   "stat_updates" => %{}, "damage" => int, "narration_context" => %{}}`
  """
  def resolve(action, character, theme, scene_facts) do
    rules = theme["rules"] || %{}

    notation = RulesEngine.dice_for(action["action_type"], character, rules)
    dc = RulesEngine.calculate_dc(action, rules)

    case Dice.roll(notation) do
      {:ok, roll_result} ->
        total = roll_result["total"] || 0
        outcome = RulesEngine.resolve_outcome(total, dc, rules)
        effects = RulesEngine.apply_effects(action, outcome, character, rules)

        result = %{
          "rolls" => roll_result["rolls"] || [],
          "total" => total,
          "dc" => dc,
          "outcome" => outcome,
          "stat_updates" => effects["stat_updates"],
          "damage" => effects["damage"],
          "narration_context" => %{
            "character_name" => character["name"],
            "action_type" => action["action_type"],
            "target" => action["target_id"],
            "notation" => notation,
            "scene_facts" => scene_facts
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
