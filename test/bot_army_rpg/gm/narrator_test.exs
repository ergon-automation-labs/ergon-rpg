defmodule BotArmyRpg.GM.NarratorTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyRpg.GM.Narrator
  alias BotArmyRpg.Themes.IronKingdoms

  defmodule StubPublisher do
    @moduledoc false
    def request(_subject, _payload, _opts), do: {:error, :unavailable}
    def publish(_subject, _payload), do: :ok
    def publish(_subject, _payload, _opts), do: :ok
  end

  defmodule SpeakingPublisher do
    @moduledoc false
    # The bot's real shape: the completion, unwrapped, under `"completion"`.
    def request("llm.prompt.submit", %{"text" => text}, _opts) when is_binary(text),
      do: {:ok, %{"completion" => "The GM's own words.", "model" => "stub"}}

    def request(_subject, _payload, _opts), do: {:error, :unavailable}
    def publish(_subject, _payload), do: :ok
    def publish(_subject, _payload, _opts), do: :ok
  end

  defmodule RefusingPublisher do
    @moduledoc false
    def request(_subject, _payload, _opts),
      do: {:ok, %{"error" => ":empty_prompt", "prompt_id" => "226e8fbb"}}

    def publish(_subject, _payload), do: :ok
    def publish(_subject, _payload, _opts), do: :ok
  end

  setup do
    Application.put_env(:bot_army_rpg, :nats_publisher, StubPublisher)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :nats_publisher)
    end)

    :ok
  end

  describe "narrate_action/4 fallback prose" do
    test "uses the themed persona title when the theme reskins the bot" do
      theme = IronKingdoms.theme()
      character = %{"bot_id" => "gtd", "name" => "Gtd"}
      action = %{"action_type" => "attack", "description" => "Gtd strikes at the enemy."}
      resolution = %{"outcome" => "success", "total" => 14, "dc" => 12}

      assert {:ok, narration} = Narrator.narrate_action(action, resolution, theme, character)

      assert narration =~ "the Gobber Tinker"
      assert narration =~ "barrage"
    end

    test "falls back to character name when the theme does not reskin the bot" do
      theme = %{"vocabulary" => %{"attack" => "strike"}}
      character = %{"bot_id" => "some_unknown_bot", "name" => "Stranger"}
      action = %{"action_type" => "attack", "description" => "Stranger lashes out."}
      resolution = %{"outcome" => "success", "total" => 14, "dc" => 12}

      assert {:ok, narration} = Narrator.narrate_action(action, resolution, theme, character)
      assert narration =~ "Stranger"
    end

    test "uses action description when no character is provided" do
      theme = IronKingdoms.theme()
      action = %{"action_type" => "attack", "description" => "An anonymous attacker"}
      resolution = %{"outcome" => "success", "total" => 14, "dc" => 12}

      assert {:ok, narration} = Narrator.narrate_action(action, resolution, theme)
      assert narration =~ "An anonymous attacker"
    end

    test "renders themed prose for each outcome band" do
      theme = IronKingdoms.theme()
      character = %{"bot_id" => "synapse", "name" => "Synapse"}
      action = %{"action_type" => "attack", "description" => "Synapse strikes."}

      for {outcome, marker} <- [
            {"critical_success", "masterful"},
            {"success", "with skill"},
            {"failure", "falls short"},
            {"critical_failure", "disastrously"}
          ] do
        resolution = %{"outcome" => outcome, "total" => 14, "dc" => 12}

        assert {:ok, narration} = Narrator.narrate_action(action, resolution, theme, character)
        assert narration =~ "the Iosan Envoy", "outcome=#{outcome}: missing themed label"
        assert narration =~ marker, "outcome=#{outcome}: missing marker #{inspect(marker)}"
      end
    end
  end

  describe "the LLM call" do
    test "the prompt is sent in the field the bot reads, and the prose is its answer" do
      Application.put_env(:bot_army_rpg, :nats_publisher, SpeakingPublisher)

      assert {:ok, "The GM's own words."} =
               Narrator.narrate_action(
                 %{"action_type" => "attack", "description" => "She strikes."},
                 %{"outcome" => "success"},
                 IronKingdoms.theme()
               )
    end

    test "an answer that is not prose is a failure, never narration" do
      # Measured live 2026-10-26: the fact written for a turn was
      # `%{"error" => ":empty_prompt", "prompt_id" => …}` — the refusal, inspected, dressed
      # as the GM's prose. The template speaks instead.
      Application.put_env(:bot_army_rpg, :nats_publisher, RefusingPublisher)

      assert {:ok, narration} =
               Narrator.narrate_action(
                 %{"action_type" => "attack", "description" => "She strikes."},
                 %{"outcome" => "success"},
                 IronKingdoms.theme()
               )

      refute narration =~ "error"
      refute narration =~ "prompt_id"
      assert narration =~ "She strikes."
    end
  end
end
