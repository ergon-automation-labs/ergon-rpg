defmodule BotArmyRpg.FailureAnalyzerTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.FailureAnalyzer

  test "analyze returns structured failure analysis" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.15,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.5,
        success_band: "partial_success",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.7,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")

    assert result["version"] == "1.0"
    assert result["category"] == "job_search"
    assert result["analyzed_at"]
    assert is_map(result["window"])
    assert result["window"]["total"] == 5
    assert result["window"]["failures"] == 3
    assert result["window"]["rate"] == 0.6
    assert is_map(result["outcome_distribution"])
    assert is_list(result["patterns"])
    assert is_list(result["prescriptive_hints"])
  end

  test "detects catastrophic_dominant pattern" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.15,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.5,
        success_band: "partial_success",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    patterns = result["patterns"]

    assert Enum.any?(patterns, fn p -> p["type"] == "catastrophic_dominant" end)

    assert Enum.any?(result["prescriptive_hints"], fn h ->
             h["pattern"] == "catastrophic_dominant"
           end)
  end

  test "detects consecutive_streak pattern" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.15,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.25,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.8,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    patterns = result["patterns"]

    streak_pattern = Enum.find(patterns, fn p -> p["type"] == "consecutive_streak" end)
    assert streak_pattern
    assert streak_pattern["streak_length"] == 4
    assert streak_pattern["severity"] == "high"
  end

  test "detects declining_trend pattern" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.9,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.85,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.3,
        success_band: "complication",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.25,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    patterns = result["patterns"]

    assert Enum.any?(patterns, fn p -> p["type"] == "declining_trend" end)
  end

  test "detects rapid_retry pattern" do
    # 12 hour gap between each attempt
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 00:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.15,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 06:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.25,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 18:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    patterns = result["patterns"]

    # 6 hours average gap between attempts (rapid)
    assert Enum.any?(patterns, fn p -> p["type"] == "rapid_retry" end)
  end

  test "detects improving_trend pattern" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.25,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.7,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.8,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.9,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    patterns = result["patterns"]

    assert Enum.any?(patterns, fn p -> p["type"] == "improving_trend" end)
  end

  test "outcome_distribution counts by success_band" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.95,
        success_band: "critical_success",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.85,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.5,
        success_band: "partial_success",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.3,
        success_band: "complication",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      }
    ]

    result = FailureAnalyzer.analyze(quests, "job_search")
    dist = result["outcome_distribution"]

    assert dist["critical_success"] == 1
    assert dist["full_success"] == 1
    assert dist["partial_success"] == 1
    assert dist["complication"] == 1
    assert dist["catastrophic_failure"] == 1
  end
end
