defmodule BotArmyRpg.QuestEngine do
  @moduledoc """
  Generates quests from GTD tasks/projects with narrative framing and rewards.

  Quests are derived from high-priority GTD items:
  - High/Urgent priority → Epic/Legendary quests (2x-3x XP multiplier)
  - Normal priority → Uncommon quests (1.5x XP multiplier)
  - Low priority → Common quests (1x XP multiplier)

  Each quest has:
  - Narrative framing (generated or templated)
  - Rewards (XP multiplier, potential loot drops on completion)
  - Progress tracking (linked to GTD task)
  - Status (active, completed, abandoned)
  """

  @quest_templates %{
    "high" => [
      "The Council demands your immediate attention: **%{title}**. Failure is not an option.",
      "A dire matter requires your expertise: **%{title}**. Lives may depend on your success.",
      "A critical task has arisen: **%{title}**. The stakes have never been higher."
    ],
    "normal" => [
      "A request arrives: **%{title}**. Your assistance would be greatly appreciated.",
      "An opportunity presents itself: **%{title}**. This could prove worthwhile.",
      "A task awaits: **%{title}**. Will you take on this challenge?"
    ],
    "low" => [
      "A minor task is available: **%{title}**. Easy coin for those interested.",
      "A simple matter: **%{title}**. Minimal effort required.",
      "A routine task: **%{title}**. Few would find this challenging."
    ]
  }

  @doc """
  Create a quest from a GTD task/project.

  Takes GTD item data and returns quest object with:
  - id, title, description, narrative_framing
  - priority, status, progress
  - rewards: xp_multiplier, potential_loot_rarity
  - linked_gtd_id (for progress tracking)
  """
  def create_from_gtd_task(gtd_task) when is_map(gtd_task) do
    quest_id = Ecto.UUID.generate()
    title = Map.get(gtd_task, "title", "Unnamed Task")
    priority = Map.get(gtd_task, "priority", "normal")
    description = Map.get(gtd_task, "description", "")
    gtd_id = Map.get(gtd_task, "id")

    {xp_multiplier, loot_rarity} = rewards_for_priority(priority)
    narrative = generate_narrative(priority, title)

    %{
      "id" => quest_id,
      "title" => title,
      "description" => description,
      "narrative_framing" => narrative,
      "priority" => priority,
      "status" => "active",
      "progress" => %{
        "steps_total" => 1,
        "steps_completed" => 0
      },
      "rewards" => %{
        "xp_multiplier" => xp_multiplier,
        "potential_loot_rarity" => loot_rarity
      },
      "linked_gtd_id" => gtd_id,
      "source_category" => Map.get(gtd_task, "source_category") || Map.get(gtd_task, "category"),
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Mark quest as in_progress (task started).
  """
  def mark_in_progress(quest) when is_map(quest) do
    Map.put(quest, "status", "in_progress")
  end

  @doc """
  Mark quest as completed with rewards calculation.

  Returns: %{"status" => "completed", "rewards_earned" => {...}, ...}

  Accepts optional success_band to record outcome tier.
  """
  def mark_completed(quest, character_level, opts \\ []) when is_map(quest) do
    xp_multiplier = get_in(quest, ["rewards", "xp_multiplier"]) || 1.0
    success_band = Keyword.get(opts, :success_band)
    outcome_score = outcome_score_for_band(success_band)

    completed_quest =
      quest
      |> Map.put("status", "completed")
      |> Map.put("completed_at", DateTime.utc_now() |> DateTime.to_iso8601())

    # Apply outcome modifier to XP
    effective_multiplier = xp_multiplier * (outcome_score || 1.0)
    base_xp = 100
    xp_reward = trunc(base_xp * character_level * effective_multiplier)

    completed_quest =
      completed_quest
      |> Map.put("rewards_earned", %{
        "xp" => xp_reward,
        "bonus_multiplier" => effective_multiplier
      })

    # Record outcome if provided
    if success_band do
      completed_quest
      |> Map.put("success_band", success_band)
      |> Map.put("outcome_score", outcome_score)
    else
      completed_quest
    end
  end

  @doc """
  Maps success band to outcome score (0.0 - 1.0).
  """
  def outcome_score_for_band("critical_success"), do: 1.0
  def outcome_score_for_band("full_success"), do: 0.8
  def outcome_score_for_band("partial_success"), do: 0.5
  def outcome_score_for_band("complication"), do: 0.2
  def outcome_score_for_band("catastrophic_failure"), do: 0.0
  def outcome_score_for_band(_), do: 1.0

  @doc """
  Get quest progress as a percentage.
  """
  def progress_percentage(quest) when is_map(quest) do
    progress = Map.get(quest, "progress", %{})
    steps_total = Map.get(progress, "steps_total", 1)
    steps_completed = Map.get(progress, "steps_completed", 0)

    if steps_total == 0, do: 0, else: trunc(steps_completed / steps_total * 100)
  end

  defp rewards_for_priority("high"), do: {3.0, "rare"}
  defp rewards_for_priority("urgent"), do: {3.0, "epic"}
  defp rewards_for_priority("normal"), do: {1.5, "uncommon"}
  defp rewards_for_priority("low"), do: {1.0, "common"}
  defp rewards_for_priority(_), do: {1.0, "common"}

  defp generate_narrative(priority, title) do
    templates = Map.get(@quest_templates, priority, Map.get(@quest_templates, "normal"))
    template = Enum.random(templates)
    String.replace(template, "%{title}", title)
  end
end
