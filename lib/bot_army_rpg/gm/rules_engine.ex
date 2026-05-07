defmodule BotArmyRpg.GM.RulesEngine do
  @moduledoc """
  Pure functions for interpreting theme rules and resolving actions.

  Operates on the `rules` jsonb map stored in a theme.
  """

  @doc """
  Build dice notation for an action from character stats and theme rules.

  Falls back to `"1d20"` if no rules are present.
  """
  def dice_for(action_type, character, rules) do
    base = rules["dice_notation"] || "1d20"
    stat_key = stat_for_action(action_type, rules)
    modifier = stat_modifier(character, stat_key)

    if modifier == 0 do
      base
    else
      sign = if modifier > 0, do: "+", else: ""
      "#{base}#{sign}#{modifier}"
    end
  end

  @doc """
  Calculate a target DC from action context and theme rules.
  """
  def calculate_dc(action_context, rules) do
    base_dc = get_in(rules, ["check", "dc_standard"]) || 15

    difficulty = action_context["difficulty"] || "normal"

    modifier =
      case difficulty do
        "trivial" -> -5
        "easy" -> -2
        "normal" -> 0
        "hard" -> +2
        "very_hard" -> +5
        _ -> 0
      end

    base_dc + modifier
  end

  @doc """
  Resolve the degree of success from roll total, DC, and theme rules.
  """
  def resolve_outcome(roll_total, dc, rules) do
    degrees = rules["degrees_of_success"] || %{}

    cond do
      degrees["critical_success"] == "natural 20" and roll_total == 20 ->
        "critical_success"

      roll_total >= dc + 10 ->
        "critical_success"

      roll_total >= dc ->
        "success"

      roll_total <= dc - 10 ->
        "critical_failure"

      true ->
        "failure"
    end
  end

  @doc """
  Compute stat deltas and damage from an action outcome.
  Returns a map of changes to apply to character stats.
  """
  def apply_effects(action, outcome, character, _rules) do
    action_type = action["action_type"] || "attack"
    base_damage = action["base_damage"] || 0

    damage =
      case outcome do
        "critical_success" -> base_damage * 2
        "success" -> base_damage
        "failure" -> div(base_damage, 2)
        "critical_failure" -> 0
        _ -> 0
      end

    stat_updates =
      if action_type == "defend" and outcome in ["success", "critical_success"] do
        %{"ac" => (character["stats"]["ac"] || 10) + 1}
      else
        %{}
      end

    %{
      "stat_updates" => stat_updates,
      "damage" => damage,
      "outcome" => outcome
    }
  end

  @doc """
  List valid action types from theme rules.
  """
  def valid_actions(rules) do
    rules["action_types"] || ["attack", "defend", "skill", "move", "item"]
  end

  @doc """
  Return the initiative method from theme rules.
  """
  def initiative_method(rules) do
    rules["initiative_method"] || "static_order"
  end

  # --- Private ---

  defp stat_for_action(action_type, rules) do
    mapping = rules["action_stat_mapping"] || %{}

    Map.get(mapping, action_type, default_stat_for_action(action_type))
  end

  defp default_stat_for_action("attack"), do: "str"
  defp default_stat_for_action("defend"), do: "con"
  defp default_stat_for_action("skill"), do: "int"
  defp default_stat_for_action("move"), do: "dex"
  defp default_stat_for_action("hack"), do: "int"
  defp default_stat_for_action("negotiate"), do: "cha"
  defp default_stat_for_action("evade"), do: "dex"
  defp default_stat_for_action("inspect"), do: "wis"
  defp default_stat_for_action("inspire"), do: "cha"
  defp default_stat_for_action(_), do: "str"

  defp stat_modifier(character, stat_key) do
    stats = character["stats"] || %{}
    ability_scores = stats["ability_scores"] || %{}
    score = ability_scores[stat_key] || 10
    div(score - 10, 2)
  end
end
