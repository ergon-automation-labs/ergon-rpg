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

  defmodule EchoingPublisher do
    @moduledoc """
    Hands the prompt back as the completion.

    The narrator passes any non-empty completion straight through, so the returned
    "narration" IS the prompt — which lets a test read what the GM was told without
    a side channel, a named process, or a second assertion target.
    """
    def request("llm.prompt.submit", %{"text" => text}, _opts),
      do: {:ok, %{"completion" => text}}

    def request(_subject, _payload, _opts), do: {:error, :unavailable}
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

  describe "narrate_scene/3 — the facts in the prompt" do
    # Measured 2026-10-26: the wife-care panel's "Have the GM narrate the quest"
    # answered `:handler_crashed` — `protocol String.Chars not implemented for
    # %{"category" => "narration", "content" => …}` — because the prompt builder
    # `Enum.join`ed fact ROWS. Any table with one fact in it could not be narrated,
    # and the page (which had no clause for a refusal) reset to the world picker.
    # There was no test for narrate_scene/3 at all; these are it.
    test "a fact row reaches the prompt as its sentence, not as Elixir map syntax" do
      Application.put_env(:bot_army_rpg, :nats_publisher, EchoingPublisher)

      facts = [
        %{
          "id" => "1dc5da32",
          "category" => "narration",
          "content" => "Companion Bot strikes at the enemy.",
          "source" => "gm"
        }
      ]

      assert {:ok, prompt} =
               Narrator.narrate_scene("The ruined hall", IronKingdoms.theme(), facts)

      assert prompt =~ "You are the Game Master narrating a scene"
      assert prompt =~ "Scene: The ruined hall"
      assert prompt =~ "Recent events:"
      assert prompt =~ "Companion Bot strikes at the enemy."
      refute prompt =~ "%{"
      refute prompt =~ "category"
    end

    test "a plain string fact is prose already and is kept as written" do
      Application.put_env(:bot_army_rpg, :nats_publisher, EchoingPublisher)

      assert {:ok, prompt} =
               Narrator.narrate_scene("A door", IronKingdoms.theme(), ["A door closes."])

      assert prompt =~ "A door closes."
      refute prompt =~ "%{"
    end

    test "a fact the prompt cannot read as prose is left out, not inspected in" do
      Application.put_env(:bot_army_rpg, :nats_publisher, EchoingPublisher)

      facts = [%{"category" => "narration"}, 42, "The torch gutter."]

      assert {:ok, prompt} = Narrator.narrate_scene("The hall", IronKingdoms.theme(), facts)

      assert prompt =~ "The torch gutter."
      refute prompt =~ "%{"
      refute prompt =~ "42"
    end

    test "an empty table says nothing about recent events" do
      Application.put_env(:bot_army_rpg, :nats_publisher, EchoingPublisher)

      for facts <- [[], nil] do
        assert {:ok, prompt} = Narrator.narrate_scene("The hall", IronKingdoms.theme(), facts)
        refute prompt =~ "Recent events"
      end
    end

    # What this used to assert was the crash's *replacement*: rows were `Enum.join`ed, the
    # handler raised, and the fix was a template that spoke when the model could not. The
    # template interpolated the scene description — which on a real table is a GTD task
    # title — so the fix was honest about not crashing and dishonest about what the GM
    # said. A table with facts and no model is a *failure the caller is told about*.
    test "a session with facts is asked, and a missing model is a failure not a template" do
      facts = [%{"category" => "narration", "content" => "Companion Bot strikes at the enemy."}]

      assert {:error, :unavailable} =
               Narrator.narrate_scene("The ruined hall", IronKingdoms.theme(), facts)
    end
  end

  describe "narrate_scene/3 — a model that does not answer" do
    # The old shape answered with a template: "You find yourself in <the quest's title>.
    # The air of <setting> feels <tone>." With the LLM bot degraded to
    # `:no_providers_available` (measured on mini 2026-10-26 15:52 MDT) that painted a GTD
    # task title as a place the GM had described, and the page had no way to tell it apart
    # from prose. A scene is the model's words or it is a failure; the caller says which.
    test "a refusal is a failure, not a scene the GM never described" do
      Application.put_env(:bot_army_rpg, :nats_publisher, RefusingPublisher)

      assert {:error, {:llm_error, ":empty_prompt"}} =
               Narrator.narrate_scene(
                 "Docs.2 — Write the pattern and the rule in docs/technical/ERROR_MESSAGE_PATTERN.md",
                 IronKingdoms.theme(),
                 []
               )
    end

    test "an unreachable model is a failure too" do
      Application.put_env(:bot_army_rpg, :nats_publisher, StubPublisher)

      assert {:error, :unavailable} =
               Narrator.narrate_scene("The ruined hall", IronKingdoms.theme(), [])
    end
  end

  describe "narrate_action/4 fallback prose" do
    test "uses the themed persona's name when the theme reskins the bot" do
      theme = IronKingdoms.theme()
      character = %{"bot_id" => "gtd", "name" => "Gtd"}
      action = %{"action_type" => "attack", "description" => "Gtd strikes at the enemy."}
      resolution = %{"outcome" => "success", "total" => 14, "dc" => 12}

      assert {:ok, narration} = Narrator.narrate_action(action, resolution, theme, character)

      assert narration =~ "Sprix"
      refute narration =~ "Gobber Tinker"
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
        assert narration =~ "Aelindra of House Shyeel", "outcome=#{outcome}: missing persona name"
        assert narration =~ marker, "outcome=#{outcome}: missing marker #{inspect(marker)}"
      end
    end
  end

  describe "fallback prose for a theme whose action names carry a description" do
    @neon_theme %{
      "vocabulary" => %{"hack" => "ICE through the black market net"},
      "npc_personas" => %{}
    }

    defp neon_line(action_type, outcome, name \\ "Eir") do
      character = %{"bot_id" => "companion_bot", "name" => name}
      action = %{"action_type" => action_type, "description" => "#{name} acts."}
      resolution = %{"outcome" => outcome, "total" => 14, "dc" => 12}
      {:ok, line} = Narrator.narrate_action(action, resolution, @neon_theme, character)
      line
    end

    test "says the verb, not the whole action string, and does not conjugate it with an s" do
      line =
        neon_line("conspire (work with resistance or corp double agents)", "critical_failure")

      assert line == "Eir tries to conspire, and it goes disastrously wrong!"
      refute line =~ "("
      refute line =~ "conspires"
    end

    test "each outcome has its own ending" do
      action = "persuade (negotiate with fixers, corps, or gang leaders)"

      assert neon_line(action, "critical_success") ==
               "Eir tries to persuade, and it goes brilliantly!"

      assert neon_line(action, "success") == "Eir tries to persuade, and it works."
      assert neon_line(action, "failure") == "Eir tries to persuade, but falls short."
      assert neon_line(action, "something_else") == "Eir tries to persuade."
    end

    test "a multi-word verb stays whole" do
      assert neon_line("jack in (enter cyberspace)", "success") ==
               "Eir tries to jack in, and it works."
    end

    test "the actor is the character's name, not the description sentence" do
      line = neon_line("hack (breach corporate systems or ICE)", "failure", "Mara Voss")
      assert String.starts_with?(line, "Mara Voss tries to hack")
      refute line =~ "acts."
    end

    test "a persona with a name is called by it, never by its title or the sheet's name" do
      theme = %{
        "vocabulary" => %{},
        "npc_personas" => %{
          "fixer" => %{"name" => "Mara Voss", "title" => "Fixer", "bot_assignments" => ["gtd"]}
        }
      }

      character = %{"bot_id" => "gtd_bot", "name" => "The Lorekeeper"}
      action = %{"action_type" => "hack (breach)", "description" => "Mara Voss acts."}
      resolution = %{"outcome" => "success"}

      assert {:ok, "Mara Voss tries to hack, and it works."} =
               Narrator.narrate_action(action, resolution, theme, character)
    end

    test "a persona with no name keeps its title" do
      theme = %{
        "vocabulary" => %{},
        "npc_personas" => %{"solo" => %{"title" => "Solo", "bot_assignments" => ["discord"]}}
      }

      character = %{"bot_id" => "discord", "name" => "The Herald"}
      action = %{"action_type" => "shoot (combat)", "description" => "x"}

      assert {:ok, "the Solo tries to shoot, and it works."} =
               Narrator.narrate_action(action, %{"outcome" => "success"}, theme, character)
    end

    test "an action the theme's vocabulary names exactly keeps its vocabulary phrasing" do
      assert neon_line("hack", "success") == "Eir ICE through the black market nets with skill."
    end
  end

  defmodule RecordingPublisher do
    @moduledoc false
    def request(subject, payload, _opts) do
      send(Application.get_env(:bot_army_rpg, :narrator_test_pid), {:asked, subject, payload})
      {:ok, %{"completion" => "The GM's own words."}}
    end

    def publish(_subject, _payload), do: :ok
    def publish(_subject, _payload, _opts), do: :ok
  end

  describe "where the GM's words are written" do
    setup do
      Application.put_env(:bot_army_rpg, :nats_publisher, RecordingPublisher)
      Application.put_env(:bot_army_rpg, :narrator_test_pid, self())

      on_exit(fn ->
        Application.delete_env(:bot_army_rpg, :nats_publisher)
        Application.delete_env(:bot_army_rpg, :narrator_test_pid)
        Application.delete_env(:bot_army_rpg, :llm_source)
      end)
    end

    test "a scene is asked of the local models by default, so another provider's open breaker cannot refuse it" do
      assert {:ok, _} = Narrator.narrate_scene("a rooftop", IronKingdoms.theme(), [])

      assert_received {:asked, "llm.prompt.submit", payload}
      assert payload["source"] == "local_ollama"
      assert is_binary(payload["text"])
    end

    test "so is an action, and so is a mission's opening scene" do
      assert {:ok, _} =
               Narrator.narrate_action(
                 %{"action_type" => "attack", "description" => "x"},
                 %{"outcome" => "success"},
                 IronKingdoms.theme()
               )

      assert_received {:asked, "llm.prompt.submit", %{"source" => "local_ollama"}}

      assert {:ok, _} = Narrator.set_scene(IronKingdoms.theme())
      assert_received {:asked, "llm.prompt.submit", %{"source" => "local_ollama"}}
    end

    test "the source is configuration: set to nil, the request names none and walks the default chain" do
      Application.put_env(:bot_army_rpg, :llm_source, nil)
      assert {:ok, _} = Narrator.narrate_scene("a rooftop", IronKingdoms.theme(), [])

      assert_received {:asked, "llm.prompt.submit", payload}
      refute Map.has_key?(payload, "source")
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
