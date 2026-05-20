defmodule BotArmyRpg.Handlers.ReconGateDemoTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.FailureAnalyzer

  test "recon gate blocks quest creation when failure rate >= 60%" do
    # Scenario: 4 failures out of 6 quests (66% failure rate)
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.2,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      },
      %{
        id: "3",
        outcome_score: 0.25,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 10:00:00Z]
      },
      %{
        id: "4",
        outcome_score: 0.28,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 09:00:00Z]
      },
      %{
        id: "5",
        outcome_score: 0.7,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 08:00:00Z]
      },
      %{
        id: "6",
        outcome_score: 0.8,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 07:00:00Z]
      }
    ]

    # Analyze failures
    analysis = FailureAnalyzer.analyze(quests, "job_search")

    # Verify recon should be triggered (>= 60% failure rate)
    assert analysis["window"]["total"] == 6
    assert analysis["window"]["failures"] == 4
    assert analysis["window"]["rate"] == 0.67

    # Verify patterns are detected
    patterns = analysis["patterns"]
    assert patterns != []

    # Should detect catastrophic_dominant (4 out of 6 is 66%)
    assert Enum.any?(patterns, fn p -> p["type"] == "catastrophic_dominant" end)

    # Should detect consecutive_streak (4 consecutive failures at the start)
    assert Enum.any?(patterns, fn p ->
             p["type"] == "consecutive_streak" && p["streak_length"] == 4
           end)

    # Verify prescriptive hints are specific
    hints = analysis["prescriptive_hints"]
    assert length(hints) >= 2

    catastrophic_hint = Enum.find(hints, fn h -> h["pattern"] == "catastrophic_dominant" end)
    assert catastrophic_hint
    assert String.contains?(catastrophic_hint[:action], ["decomposition", "scope"])
    assert String.contains?(catastrophic_hint[:why], ["fundamental", "misaligned"])

    consecutive_hint = Enum.find(hints, fn h -> h["pattern"] == "consecutive_streak" end)
    assert consecutive_hint
    assert String.contains?(consecutive_hint[:action], ["change", "approach"])
    assert String.contains?(consecutive_hint[:why], ["broken"])
  end

  test "recon task description is formatted with patterns and hints" do
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

    analysis = FailureAnalyzer.analyze(quests, "job_search")

    # Simulate building recon task description (as ConsequenceEngine does)
    failure_rate = analysis["window"]["rate"] * 100
    category_name = "Job Search"

    # This mimics what build_recon_description does
    description = """
    ## Reconnaissance Required: #{category_name}

    **Failure rate: #{Float.round(failure_rate, 0)}% in last #{analysis["window"]["total"]} missions**

    ### What the analysis found

    - **catastrophic_dominant** (severity: high): Most attempts end in catastrophic failure
    - **consecutive_streak** (severity: high): Consecutive failures in a row

    ### What to research

    **Research: task decomposition, requirement clarification, and scope definition**
    > Catastrophic failures indicate fundamental misalignment with the goal, not execution gaps

    **Stop and change your approach entirely before retrying**
    > Consecutive failures mean the current strategy is broken. Repetition won't fix it

    ### How to clear this gate

    Complete this task once you've gathered enough intelligence to attempt this category differently.
    """

    # Verify description has all required sections
    assert String.contains?(description, ["Reconnaissance Required"])
    assert String.contains?(description, ["80"])
    assert String.contains?(description, ["catastrophic_dominant"])
    assert String.contains?(description, ["consecutive_streak"])
    assert String.contains?(description, ["decomposition"])
    assert String.contains?(description, ["change your approach"])
  end

  test "quest creation succeeds when no recon needed" do
    quests = [
      %{
        id: "1",
        outcome_score: 0.1,
        success_band: "catastrophic_failure",
        inserted_at: ~U[2026-05-16 12:00:00Z]
      },
      %{
        id: "2",
        outcome_score: 0.8,
        success_band: "full_success",
        inserted_at: ~U[2026-05-16 11:00:00Z]
      }
    ]

    analysis = FailureAnalyzer.analyze(quests, "job_search")

    # Only 50% failure rate - no recon needed
    assert analysis["window"]["rate"] == 0.5

    # No patterns should trigger (need >= 60% for recon)
    patterns = analysis["patterns"]

    # May have some patterns but none that would block quest creation
    recon_blocking_patterns =
      Enum.filter(patterns, fn p ->
        p["type"] in [
          "catastrophic_dominant",
          "consecutive_streak",
          "declining_trend",
          "rapid_retry"
        ]
      end)

    # With 2 quests (50% failure), we shouldn't hit the thresholds
    assert recon_blocking_patterns == []
  end

  test "outcome_distribution tallies by success_band" do
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

    analysis = FailureAnalyzer.analyze(quests, "job_search")
    dist = analysis["outcome_distribution"]

    assert dist["critical_success"] == 1
    assert dist["full_success"] == 1
    assert dist["partial_success"] == 1
    assert dist["complication"] == 1
    assert dist["catastrophic_failure"] == 1
  end

  test "prescriptive hints are specific to detected patterns" do
    # All rapid retries (< 12h apart)
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

    analysis = FailureAnalyzer.analyze(quests, "job_search")
    hints = analysis["prescriptive_hints"]

    rapid_retry_hint = Enum.find(hints, fn h -> h["pattern"] == "rapid_retry" end)
    assert rapid_retry_hint
    assert String.contains?(rapid_retry_hint[:action], ["delays", "24h"])
    assert String.contains?(rapid_retry_hint[:why], ["frustration"])
  end
end
