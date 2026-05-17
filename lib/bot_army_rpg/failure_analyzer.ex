defmodule BotArmyRpg.FailureAnalyzer do
  @moduledoc """
  Analyzes quest failure patterns to generate diagnostic recon tasks.

  Given a list of recent quest outcomes, identifies patterns (streaks, trends,
  rapid retries) and generates prescriptive research hints tied to each pattern.

  Dice rolls are NOT the primary signal — analysis focuses on outcome_score
  distributions, timing, and clustering. Dice details reserved for adventure-style reports.
  """

  @hints %{
    "catastrophic_dominant" => %{
      action: "Research: task decomposition, requirement clarification, and scope definition",
      why:
        "Catastrophic failures indicate fundamental misalignment with the goal, not execution gaps. Start over conceptually."
    },
    "complication_dominant" => %{
      action: "Research: risk mitigation, contingency planning, and blocker identification",
      why:
        "Complications mean you're getting close but being derailed. Map what's blocking you and address each directly."
    },
    "consecutive_streak" => %{
      action: "Stop and change your approach entirely before retrying",
      why:
        "Consecutive failures mean the current strategy is broken. Repetition won't fix it — seek a different angle."
    },
    "declining_trend" => %{
      action:
        "Seek outside perspective — pair with someone, or research alternatives to your current method",
      why:
        "Getting worse over time means your current approach is actively compounding the problem."
    },
    "rapid_retry" => %{
      action: "Introduce deliberate delays between attempts (minimum 24h reflection)",
      why:
        "Retrying within hours suggests frustration-driven attempts which rarely succeed and often worsen patterns."
    },
    "improving_trend" => %{
      action: "Keep current approach but reduce scope of each attempt to reduce failure cost",
      why: "Things are improving — maintain momentum but protect against regression."
    }
  }

  @doc """
  Analyze quest outcomes and return structured failure analysis with patterns and hints.

  Returns a map with:
  - version, analyzed_at, category, window (size/total/failures/rate)
  - outcome_distribution (by success_band)
  - patterns (list of detected pattern maps)
  - prescriptive_hints (actionable research suggestions)
  """
  def analyze(quests, category) when is_list(quests) and is_binary(category) do
    sorted = Enum.sort_by(quests, & &1.inserted_at, :desc)
    total = length(sorted)
    failures = Enum.count(sorted, fn q -> q.outcome_score < 0.3 end)

    distribution = outcome_distribution(sorted)
    patterns = detect_patterns(sorted, total, failures)
    hints = generate_hints(patterns)

    %{
      "version" => "1.0",
      "analyzed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "category" => category,
      "window" => %{
        "size" => 10,
        "total" => total,
        "failures" => failures,
        "rate" => if(total > 0, do: Float.round(failures / total, 2), else: 0.0)
      },
      "outcome_distribution" => distribution,
      "patterns" => patterns,
      "prescriptive_hints" => hints,
      "dice_note" =>
        "Roll performance minimized in primary analysis — available in adventure after action report"
    }
  end

  defp outcome_distribution(quests) do
    bands = [
      "critical_success",
      "full_success",
      "partial_success",
      "complication",
      "catastrophic_failure"
    ]

    bands
    |> Enum.map(fn band ->
      count = Enum.count(quests, fn q -> q.success_band == band end)
      {band, count}
    end)
    |> Map.new()
  end

  defp detect_patterns(quests, total, _failures) when total > 0 do
    []
    |> check_catastrophic_dominant(quests, total)
    |> check_complication_dominant(quests, total)
    |> check_consecutive_streak(quests)
    |> check_trend(quests)
    |> check_rapid_retry(quests)
  end

  defp detect_patterns(_quests, _total, _failures), do: []

  defp check_catastrophic_dominant(patterns, quests, total) do
    catastrophic_count = Enum.count(quests, fn q -> q.success_band == "catastrophic_failure" end)

    if catastrophic_count > total * 0.5 do
      patterns ++
        [
          %{
            "type" => "catastrophic_dominant",
            "severity" => "high",
            "count" => catastrophic_count
          }
        ]
    else
      patterns
    end
  end

  defp check_complication_dominant(patterns, quests, total) do
    complication_count = Enum.count(quests, fn q -> q.success_band == "complication" end)

    if complication_count > total * 0.5 and
         !Enum.any?(patterns, &(&1["type"] == "catastrophic_dominant")) do
      patterns ++
        [
          %{
            "type" => "complication_dominant",
            "severity" => "medium",
            "count" => complication_count
          }
        ]
    else
      patterns
    end
  end

  defp check_consecutive_streak(patterns, quests) do
    # Quests are already sorted newest first, so check prefix of failures
    streaks = find_consecutive_failures(quests, 0, 0)

    case streaks do
      streak_length when streak_length >= 4 ->
        patterns ++
          [
            %{
              "type" => "consecutive_streak",
              "severity" => "high",
              "streak_length" => streak_length
            }
          ]

      streak_length when streak_length == 3 ->
        patterns ++
          [
            %{
              "type" => "consecutive_streak",
              "severity" => "medium",
              "streak_length" => streak_length
            }
          ]

      _ ->
        patterns
    end
  end

  defp find_consecutive_failures([quest | rest], count, max_streak) do
    if quest.outcome_score < 0.3 do
      find_consecutive_failures(rest, count + 1, max(count + 1, max_streak))
    else
      max(count, max_streak)
    end
  end

  defp find_consecutive_failures([], count, max_streak), do: max(count, max_streak)

  defp check_trend(patterns, quests) when length(quests) >= 4 do
    sorted_asc = Enum.sort_by(quests, & &1.inserted_at, :asc)
    mid = div(length(sorted_asc), 2)

    early = Enum.take(sorted_asc, mid)
    recent = Enum.drop(sorted_asc, mid)

    early_avg = average_score(early)
    recent_avg = average_score(recent)

    cond do
      recent_avg < early_avg - 0.15 ->
        patterns ++
          [
            %{
              "type" => "declining_trend",
              "severity" => "high",
              "early_avg" => Float.round(early_avg, 2),
              "recent_avg" => Float.round(recent_avg, 2)
            }
          ]

      recent_avg > early_avg + 0.1 ->
        patterns ++
          [
            %{
              "type" => "improving_trend",
              "severity" => "low",
              "early_avg" => Float.round(early_avg, 2),
              "recent_avg" => Float.round(recent_avg, 2)
            }
          ]

      true ->
        patterns
    end
  end

  defp check_trend(patterns, _quests), do: patterns

  defp check_rapid_retry(patterns, quests) when length(quests) >= 3 do
    sorted_asc = Enum.sort_by(quests, & &1.inserted_at, :asc)
    gaps = calculate_gaps(sorted_asc)

    if gaps != [] do
      avg_gap_hours = Enum.sum(gaps) / length(gaps)

      if avg_gap_hours < 12.0 do
        patterns ++
          [
            %{
              "type" => "rapid_retry",
              "severity" => "medium",
              "avg_gap_hours" => Float.round(avg_gap_hours, 1)
            }
          ]
      else
        patterns
      end
    else
      patterns
    end
  end

  defp check_rapid_retry(patterns, _quests), do: patterns

  defp calculate_gaps(quests) do
    quests
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [q1, q2] ->
      DateTime.diff(q2.inserted_at, q1.inserted_at, :hour)
    end)
  end

  defp average_score(quests) when length(quests) > 0 do
    quests
    |> Enum.map(& &1.outcome_score)
    |> Enum.sum()
    |> then(&(&1 / length(quests)))
  end

  defp average_score(_), do: 0.0

  defp generate_hints(patterns) do
    patterns
    |> Enum.map(&pattern_to_hint/1)
    |> Enum.reject(&is_nil/1)
  end

  defp pattern_to_hint(%{"type" => pattern_type}) do
    case Map.get(@hints, pattern_type) do
      nil ->
        nil

      hint ->
        Map.merge(hint, %{"pattern" => pattern_type})
    end
  end

  defp pattern_to_hint(_), do: nil
end
