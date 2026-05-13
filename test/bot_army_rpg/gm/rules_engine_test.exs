defmodule BotArmyRpg.GM.RulesEngineTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.GM.RulesEngine
  alias BotArmyRpg.Themes.{IronKingdoms, Pathfinder}

  describe "resolve_outcome/3 with legacy fallback (no success_bands)" do
    test "natural 20 wins crit when degrees say so" do
      rules = %{"degrees_of_success" => %{"critical_success" => "natural 20"}}
      assert "critical_success" = RulesEngine.resolve_outcome(20, 15, rules)
    end

    test "≥ dc+10 is critical_success" do
      assert "critical_success" = RulesEngine.resolve_outcome(25, 15, %{})
    end

    test "≥ dc and < dc+10 is success" do
      assert "success" = RulesEngine.resolve_outcome(16, 15, %{})
      assert "success" = RulesEngine.resolve_outcome(15, 15, %{})
    end

    test "≤ dc-10 is critical_failure" do
      assert "critical_failure" = RulesEngine.resolve_outcome(5, 15, %{})
    end

    test "everything else is failure" do
      assert "failure" = RulesEngine.resolve_outcome(10, 15, %{})
    end
  end

  describe "resolve_outcome/3 with Iron Kingdoms 2d6 ±4 bands" do
    setup do
      %{rules: IronKingdoms.theme()["rules"]}
    end

    test "≥ dc+4 is critical_success", %{rules: rules} do
      assert "critical_success" = RulesEngine.resolve_outcome(10, 6, rules)
    end

    test "between dc and dc+3 is success", %{rules: rules} do
      assert "success" = RulesEngine.resolve_outcome(8, 6, rules)
      assert "success" = RulesEngine.resolve_outcome(6, 6, rules)
    end

    test "≤ dc-4 is critical_failure", %{rules: rules} do
      assert "critical_failure" = RulesEngine.resolve_outcome(2, 6, rules)
      assert "critical_failure" = RulesEngine.resolve_outcome(4, 8, rules)
    end

    test "between dc-3 and dc-1 is failure", %{rules: rules} do
      assert "failure" = RulesEngine.resolve_outcome(5, 6, rules)
      assert "failure" = RulesEngine.resolve_outcome(3, 6, rules)
    end

    test "the d20 ±10 chassis cannot fire on 2d6 (regression for old bug)", %{rules: rules} do
      # On 2d6 max roll is 12, so dc+10 with dc=6 means roll≥16 — impossible.
      # The new band walker must still produce a sane outcome.
      for roll <- 2..12, dc <- 4..12 do
        outcome = RulesEngine.resolve_outcome(roll, dc, rules)

        assert outcome in ~w(critical_success success failure critical_failure),
               "roll=#{roll} dc=#{dc} produced #{inspect(outcome)}"
      end
    end
  end

  describe "resolve_outcome/3 with Pathfinder preset" do
    setup do
      %{rules: Pathfinder.theme()["rules"]}
    end

    test "natural 20 always crits via eq_max", %{rules: rules} do
      assert "critical_success" = RulesEngine.resolve_outcome(20, 999, rules)
    end

    test "≥ dc+10 is critical_success", %{rules: rules} do
      assert "critical_success" = RulesEngine.resolve_outcome(25, 15, rules)
    end

    test "≥ dc and < dc+10 is success", %{rules: rules} do
      assert "success" = RulesEngine.resolve_outcome(16, 15, rules)
      assert "success" = RulesEngine.resolve_outcome(15, 15, rules)
    end

    test "≤ dc-10 is critical_failure", %{rules: rules} do
      assert "critical_failure" = RulesEngine.resolve_outcome(5, 15, rules)
    end

    test "between dc-9 and dc-1 is failure", %{rules: rules} do
      assert "failure" = RulesEngine.resolve_outcome(10, 15, rules)
    end
  end

  describe "dice_for/3" do
    test "uses resolution.dice when present" do
      rules = %{"resolution" => %{"dice" => "2d6"}}
      character = %{"stats" => %{"ability_scores" => %{"str" => 14}}}

      assert "2d6+2" = RulesEngine.dice_for("attack", character, rules)
    end

    test "falls back to dice_notation" do
      rules = %{"dice_notation" => "3d6"}
      character = %{"stats" => %{"ability_scores" => %{"str" => 10}}}

      assert "3d6" = RulesEngine.dice_for("attack", character, rules)
    end

    test "defaults to 1d20" do
      character = %{"stats" => %{"ability_scores" => %{"str" => 12}}}
      assert "1d20+1" = RulesEngine.dice_for("attack", character, %{})
    end
  end
end
