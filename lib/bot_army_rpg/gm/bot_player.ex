defmodule BotArmyRpg.GM.BotPlayer do
  @moduledoc """
  Heuristic decision-making for bot-controlled characters.

  Maps character class + optional Soul play_style to action choices.
  No LLM calls — pure heuristic for speed and predictability.
  """

  alias BotArmyRpg.GM.RulesEngine

  @doc """
  Decide an action for a bot character in a session.

  Returns `%{"action_type" => ..., "target_id" => ..., "description" => ...}`
  """
  def decide_action(_bot_id, character, _session, theme) do
    class = character["class"] || "Adventurer"
    rules = theme["rules"] || %{}
    valid = RulesEngine.valid_actions(rules)

    action_type = class_action(class, valid)

    %{
      "action_type" => action_type,
      "target_id" => nil,
      "description" => default_description(action_type, character["name"]),
      "base_damage" => default_damage(action_type)
    }
  end

  # --- Class → action mapping ---

  defp class_action("Scheduler", valid), do: pick(valid, "buff", "skill", "attack")
  defp class_action("Oracle", valid), do: pick(valid, "inspect", "skill", "defend")
  defp class_action("Bard", valid), do: pick(valid, "inspire", "negotiate", "attack")
  defp class_action("Sentinel", valid), do: pick(valid, "defend", "attack", "inspect")
  defp class_action("Drillmaster", valid), do: pick(valid, "attack", "defend", "move")
  defp class_action("Shapeshifter", valid), do: pick(valid, "evade", "skill", "attack")
  defp class_action("Steward", valid), do: pick(valid, "defend", "buff", "skill")
  defp class_action("Fixer", valid), do: pick(valid, "negotiate", "hack", "attack")
  defp class_action("Herald", valid), do: pick(valid, "inspire", "inspect", "negotiate")
  defp class_action("Scribe", valid), do: pick(valid, "inspect", "skill", "defend")
  defp class_action("Archivist", valid), do: pick(valid, "inspect", "defend", "skill")
  defp class_action(_, valid), do: pick(valid, "attack", "skill", "defend")

  defp pick(valid, a, b, c) do
    cond do
      a in valid -> a
      b in valid -> b
      c in valid -> c
      true -> List.first(valid) || "attack"
    end
  end

  defp default_description("attack", name), do: "#{name} strikes at the enemy."
  defp default_description("defend", name), do: "#{name} raises their guard."
  defp default_description("buff", name), do: "#{name} bolsters an ally."
  defp default_description("inspire", name), do: "#{name} rallies the party."
  defp default_description("inspect", name), do: "#{name} surveys the scene."
  defp default_description("negotiate", name), do: "#{name} attempts to parley."
  defp default_description("hack", name), do: "#{name} breaches the system."
  defp default_description("evade", name), do: "#{name} ducks and weaves."
  defp default_description("skill", name), do: "#{name} uses a special technique."
  defp default_description("move", name), do: "#{name} repositions."
  defp default_description(_, name), do: "#{name} acts."

  defp default_damage("attack"), do: 6
  defp default_damage("hack"), do: 4
  defp default_damage(_), do: 0
end
