defmodule BotArmyRpg.GM.Narrator do
  @moduledoc """
  Builds prompts and calls the LLM bot for GM narration.

  Action beats fall back to a sentence derived from the resolution — the bot knows what
  the roll was, so that sentence is a *report*, not an invention. A **scene** does not
  fall back at all: the template that used to speak here interpolated the quest's title,
  so a model that was down got painted as the GM saying "You find yourself in Docs.2 —
  Write the pattern and the rule in docs/technical/ERROR_MESSAGE_PATTERN.md." Measured
  2026-10-26 15:52 MDT on mini, with the LLM bot degraded to `:no_providers_available`.
  A model that does not answer is not a scene, and the caller is told so.

  When the current theme reskins a bot's archetype (see
  `BotArmyRpg.Themes.Archetype`), the actor's themed identity is woven into
  both the LLM prompt and the fallback prose without mutating the character
  row.
  """

  require Logger

  alias BotArmyRpg.Themes.Archetype

  # How long a model may take before its answer is declared missing. Three seconds was a
  # deadline the model never met: the real scene prompt (theme + vocabulary + the table's
  # facts) measured 7.5 s once and 31.6 s once on 2026-10-26, and the runtime's circuit
  # breaker answers the *first* timeout with a 60 s cooldown — so one slow answer turned
  # the whole next minute into template prose. A local model is not late at three
  # seconds; it is just still writing. `rpg.scene.narrate` now accepts "async": true so
  # the caller that must not wait (a LiveView) can be answered at once and read the prose
  # back; this ceiling is only the point at which a *prompt* is declared unanswered.
  @llm_timeout_ms 180_000
  @circuit_breaker_key "rpg:gm:llm.narrate"

  @doc """
  Narrate a scene using theme vocabulary and templates.

  Returns `{:ok, String.t()}` or `{:error, reason}`.
  """
  def narrate_scene(scene_description, theme, recent_facts) do
    call_llm(build_scene_prompt(scene_description, theme, recent_facts))
  end

  @doc """
  Narrate an action resolution using theme vocabulary.

  Pass `character` (the actor's character map, including `"bot_id"`) to
  enable theme-aware archetype hints; otherwise narration falls back to the
  raw action description.

  Returns `{:ok, String.t()}` or `{:error, reason}`.
  """
  def narrate_action(action, resolution, theme, character \\ nil) do
    archetype = Archetype.for_character(theme, character || %{})
    prompt = build_action_prompt(action, resolution, theme, archetype)

    case call_llm(prompt) do
      {:ok, text} -> {:ok, text}
      {:error, _} -> {:ok, fallback_action(action, resolution, theme, archetype, character)}
    end
  end

  # --- Prompt builders ---

  # A fact is a ROW (a map with `content`, `category`, `source`, …), and the prompt
  # wants the sentence inside it. `Enum.join(facts, "\n")` reads as prose and isn't:
  # it demands `String.Chars` of a map and *raises* out of the handler. Measured
  # 2026-10-26 — the wife-care panel's "Have the GM narrate the quest" answered
  # `:handler_crashed` with `protocol String.Chars not implemented for
  # %{"category" => "narration", "content" => "Companion Bot strikes at the enemy…"}`
  # whenever the session had a single fact in it, so a table with any history could
  # not be narrated at all. Prose in, prose out: a row we cannot read as prose is
  # left out rather than inspected into the prompt.
  defp fact_lines(nil), do: []

  defp fact_lines(facts) when is_list(facts) do
    facts
    |> Enum.map(&fact_line/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp fact_lines(_other), do: []

  defp fact_line(fact) when is_binary(fact), do: String.trim(fact)

  defp fact_line(%{"content" => content}) when is_binary(content), do: String.trim(content)
  defp fact_line(%{content: content}) when is_binary(content), do: String.trim(content)
  defp fact_line(_other), do: ""

  defp build_scene_prompt(scene_description, theme, recent_facts) do
    setting = theme["setting"] || "unknown realm"
    tone = theme["tone"] || "neutral"
    vocab = theme["vocabulary"] || %{}

    facts_text =
      case fact_lines(recent_facts) do
        [] -> ""
        lines -> "Recent events:\n" <> Enum.join(lines, "\n")
      end

    vocab_text =
      if vocab == %{} do
        ""
      else
        "Vocabulary: " <> Enum.map_join(vocab, ", ", fn {k, v} -> "#{k} → #{v}" end)
      end

    """
    You are the Game Master narrating a scene in a #{setting} setting with a #{tone} tone.

    #{vocab_text}

    Scene: #{scene_description || "An unremarkable location."}

    #{facts_text}

    Respond with a single paragraph of vivid narration (3-5 sentences).
    """
    |> String.trim()
  end

  defp build_action_prompt(action, resolution, theme, archetype) do
    setting = theme["setting"] || "unknown realm"
    tone = theme["tone"] || "neutral"
    vocab = theme["vocabulary"] || %{}

    name = action["description"] || "Someone"
    action_type = action["action_type"] || "acts"
    total = resolution["total"]
    dc = resolution["dc"]
    outcome = resolution["outcome"]

    vocab_text =
      if vocab == %{} do
        ""
      else
        "Use these vocabulary substitutions where natural: " <>
          Enum.map_join(vocab, ", ", fn {k, v} -> "#{k} → #{v}" end) <> "."
      end

    archetype_text = Archetype.prompt_hint(archetype)

    """
    You are the Game Master narrating an action in a #{setting} setting with a #{tone} tone.

    #{vocab_text}

    #{archetype_text}

    #{name} attempts a #{action_type}.
    Roll: #{total} vs DC #{dc}. Outcome: #{outcome}.

    Respond with a single vivid sentence describing what happens.
    """
    |> String.trim()
  end

  # --- LLM call ---

  # `llm.prompt.submit` reads the prompt from `"text"` and answers the completion under
  # `"completion"`, unwrapped. This sent `%{"prompt" => …}` and read `data["text"] ||
  # data["response"] || inspect(data)`, so every narration the fleet ever produced was the
  # *inspection of the refusal*: measured 2026-10-26, a turn's fact read
  # `%{"error" => ":empty_prompt", "prompt_id" => "226e8fbb-…"}` — the bot said the prompt
  # was empty because it looked in a field nobody wrote, and rpg wrote that sentence into
  # her chronicle as prose. An answer that is not prose is a failure, never narration: the
  # template speaks instead.
  defp call_llm(prompt_text) do
    payload = %{"text" => prompt_text}

    case publisher().request("llm.prompt.submit", payload,
           timeout_ms: @llm_timeout_ms,
           circuit_breaker_key: @circuit_breaker_key
         ) do
      {:ok, %{"completion" => text}} when is_binary(text) and text != "" ->
        {:ok, text}

      {:ok, %{"error" => reason}} ->
        Logger.warning("[GM.Narrator] The LLM refused the prompt: #{inspect(reason)}")
        {:error, {:llm_error, reason}}

      {:ok, other} ->
        Logger.warning("[GM.Narrator] The LLM's answer was not prose: #{inspect(other)}")
        {:error, :unreadable_reply}

      {:error, reason} ->
        Logger.warning("[GM.Narrator] LLM narration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end

  # --- Fallbacks ---

  defp fallback_action(action, resolution, theme, archetype, character) do
    vocab = theme["vocabulary"] || %{}
    outcome = resolution["outcome"]
    verb = Map.get(vocab, action["action_type"], action["action_type"])

    actor =
      case archetype do
        {:themed, _} -> Archetype.display_label(archetype)
        _ -> action["description"] || (character && character["name"]) || "The character"
      end

    case outcome do
      "critical_success" -> "#{actor} executes a masterful #{verb}!"
      "success" -> "#{actor} #{verb}s with skill."
      "failure" -> "#{actor} #{verb}s, but falls short."
      "critical_failure" -> "#{actor} #{verb}s disastrously!"
      _ -> "#{actor} #{verb}s."
    end
  end
end
