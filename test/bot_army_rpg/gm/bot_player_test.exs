defmodule BotArmyRpg.GM.BotPlayerTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyRpg.GM.BotPlayer

  @neon_actions [
    "hack (breach corporate systems or ICE)",
    "jack in (enter cyberspace)",
    "infiltrate (corporate tower or black site)",
    "augment (install illegal implants)",
    "persuade (negotiate with fixers, corps, or gang leaders)",
    "shoot (engage in lethal combat)",
    "flee (evade corporate hunters or street violence)",
    "investigate (uncover conspiracy or AI awakening)",
    "conspire (work with resistance or corp double agents)"
  ]

  defp theme(actions), do: %{"rules" => %{"action_types" => actions}}

  defp session(round), do: %{"metadata" => %{"turn_state" => %{"round" => round}}}

  defp decide(class, actions, round \\ 1) do
    BotPlayer.decide_action(
      "x",
      %{"name" => "Eir", "class" => class},
      session(round),
      theme(actions)
    )["action_type"]
  end

  describe "a Face talks" do
    test "negotiates on odd rounds and inspires on even ones, when the theme has both" do
      plain = ["attack", "negotiate", "inspire", "evade"]
      assert decide("Face", plain, 1) == "negotiate"
      assert decide("Face", plain, 2) == "inspire"
      assert decide("Face", plain, 3) == "negotiate"
    end

    test "conspiring stands in for inspiring only when there is no inspire" do
      assert decide("Face", ["conspire (x)", "inspire", "negotiate"], 2) == "inspire"
      assert decide("Face", ["conspire (x)", "negotiate"], 1) == "negotiate"
    end

    test "a Face whose round is unknown negotiates" do
      assert BotPlayer.decide_action(
               "x",
               %{"name" => "Eir", "class" => "Face"},
               %{},
               theme(["negotiate", "inspire"])
             )[
               "action_type"
             ] == "negotiate"
    end

    test "when the theme has no inspire, a Face negotiates; with neither, she evades, never the first action" do
      assert decide("Face", ["attack", "negotiate", "evade"], 2) == "negotiate"
      assert decide("Face", ["attack", "evade"], 1) == "evade"
      assert decide("Face", ["attack", "defend"], 1) == "attack"
    end
  end

  describe "a theme whose action names carry their own description" do
    test "a Face negotiates by the theme's own word for it" do
      assert decide("Face", @neon_actions, 1) ==
               "persuade (negotiate with fixers, corps, or gang leaders)"
    end

    test "a Face's inspiring is conspiring where the theme has no inspire" do
      assert decide("Face", @neon_actions, 2) ==
               "conspire (work with resistance or corp double agents)"
    end

    test "other classes find their own actions instead of all taking the first one" do
      assert decide("Herald", @neon_actions) ==
               "persuade (negotiate with fixers, corps, or gang leaders)"

      assert decide("Fixer", @neon_actions) ==
               "persuade (negotiate with fixers, corps, or gang leaders)"

      assert decide("Shapeshifter", @neon_actions) ==
               "flee (evade corporate hunters or street violence)"
    end

    test "a word inside another word is not a match" do
      assert decide("Sentinel", ["wait", "unattackable (a trap)"]) == "wait"
    end
  end

  test "an unknown class keeps its old default" do
    assert decide("Adventurer", ["attack", "skill"]) == "attack"
  end
end
