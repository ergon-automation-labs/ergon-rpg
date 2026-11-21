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

  # How long one turn's line may be waited for. A scene is waited for as long as the job needs
  # (`BotArmyRpg.GM.LlmJob.default_wait_ms/0`); a turn's line is asked for while a request is open
  # (a player's `rpg.action.resolve`), so it gets this shorter leash and then the template speaks.
  @action_wait_ms 90_000

  @doc """
  Narrate a scene using theme vocabulary and templates.

  Returns `{:ok, String.t()}` or `{:error, reason}`.
  """
  def narrate_scene(scene_description, theme, recent_facts) do
    call_llm(build_scene_prompt(scene_description, theme, recent_facts), scene_wait_ms())
  end

  @doc """
  The GM sets the opening scene of a mission in the current theme's world.

  Like a scene narration, it has no template fallback: a model that does not answer is not
  a scene, and the caller is told so.
  """
  def set_scene(theme) do
    call_llm(build_mission_scene_prompt(theme), scene_wait_ms())
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
    prompt = build_action_prompt(action, resolution, theme, archetype, character)

    case call_llm(prompt, action_wait_ms()) do
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

  defp build_mission_scene_prompt(theme) do
    setting = theme["setting"] || "unknown realm"
    tone = theme["tone"] || "neutral"
    mechanic = theme["mechanic"] || ""

    """
    You are the Game Master of a #{setting} setting with a #{tone} tone. #{mechanic}

    A small party of adventurers is being sent on a mission. Set the opening situation: where
    they are, what is at stake, and the trouble they are about to meet.

    Tell it in the third person, about "the party": never address anyone as "you". Plain prose:
    no markdown, no bold, no lists.

    Respond with one or two sentences, no more.
    """
    |> String.trim()
  end

  defp build_action_prompt(action, resolution, theme, archetype, character) do
    setting = theme["setting"] || "unknown realm"
    tone = theme["tone"] || "neutral"
    vocab = theme["vocabulary"] || %{}

    who = who_acts(theme, action, character)
    verb = verb_of(action["action_type"])
    total = resolution["total"]
    dc = resolution["dc"]
    outcome = resolution["outcome"]

    # The list is flavor, not a script: a model given it with no instruction splices the phrases
    # verbatim ("an ICE through the black market net negotiation") and bolds them.
    vocab_text =
      if vocab == %{} do
        ""
      else
        "Flavor words for this setting, to be used sparingly and only where they read naturally - " <>
          "never quote a phrase from this list into a sentence it does not fit: " <>
          Enum.map_join(vocab, ", ", fn {k, v} -> "#{k} → #{v}" end) <> "."
      end

    archetype_text = Archetype.prompt_hint(archetype, who_name(theme, character))

    """
    You are the Game Master narrating an action in a #{setting} setting with a #{tone} tone.

    #{vocab_text}

    #{archetype_text}

    #{who} tries to #{verb}.
    Roll: #{total} vs DC #{dc}. Outcome: #{outcome}.

    Respond with a single vivid sentence describing what happens, in plain prose: no markdown, no bold, no lists.
    """
    |> String.trim()
  end

  # Who acts, by name: the character's (a persona's own name when the theme has one), and only
  # without a character does the description sentence stand in for it.
  defp who_acts(theme, action, character) do
    who_name(theme, character) || action["description"] || "Someone"
  end

  defp who_name(theme, %{"name" => name} = character) when is_binary(name) and name != "",
    do: Archetype.display_name(theme, character)

  defp who_name(_theme, _character), do: nil

  # --- LLM call ---

  # The GM's words are asked for as an async job and waited for (`BotArmyRpg.GM.LlmJob`), so a
  # prompt queued behind other callers is not timed out by a clock that ran while it waited.
  # An answer that is not prose is a failure, never narration: measured 2026-10-26, a turn's
  # fact once read `%{"error" => ":empty_prompt", ...}` - the refusal, inspected and written
  # into her chronicle as prose. The job module refuses errors, blanks and the bot's canned
  # fallback by name, and the template speaks instead.
  defp call_llm(prompt_text, wait_ms) do
    case BotArmyRpg.GM.LlmJob.ask(prompt_text, wait_ms: wait_ms) do
      {:ok, text} ->
        {:ok, text}

      {:error, reason} ->
        Logger.warning("[GM.Narrator] No words from the LLM: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp scene_wait_ms, do: BotArmyRpg.GM.LlmJob.default_wait_ms()
  defp action_wait_ms, do: Application.get_env(:bot_army_rpg, :action_wait_ms, @action_wait_ms)

  # --- Fallbacks ---

  defp fallback_action(action, resolution, theme, archetype, character) do
    vocab = theme["vocabulary"] || %{}
    outcome = resolution["outcome"]
    action_type = action["action_type"]

    actor =
      case archetype do
        {:themed, persona} ->
          persona_name(persona) || Archetype.display_label(archetype)

        _ ->
          named(theme, character) || action["description"] || "The character"
      end

    case Map.fetch(vocab, action_type) do
      {:ok, verb} -> vocabulary_line(actor, verb, outcome)
      :error -> attempt_line(actor, verb_of(action_type), outcome)
    end
  end

  defp vocabulary_line(actor, verb, outcome) do
    case outcome do
      "critical_success" -> "#{actor} executes a masterful #{verb}!"
      "success" -> "#{actor} #{verb}s with skill."
      "failure" -> "#{actor} #{verb}s, but falls short."
      "critical_failure" -> "#{actor} #{verb}s disastrously!"
      _ -> "#{actor} #{verb}s."
    end
  end

  # An action the vocabulary does not name is told as an attempt, so the verb stands as the
  # theme wrote it and is never conjugated.
  defp attempt_line(actor, verb, outcome) do
    case outcome do
      "critical_success" -> "#{actor} tries to #{verb}, and it goes brilliantly!"
      "success" -> "#{actor} tries to #{verb}, and it works."
      "failure" -> "#{actor} tries to #{verb}, but falls short."
      "critical_failure" -> "#{actor} tries to #{verb}, and it goes disastrously wrong!"
      _ -> "#{actor} tries to #{verb}."
    end
  end

  # A theme may write an action as "persuade (negotiate with fixers...)": the verb is what
  # comes before the description.
  @doc false
  def verb_of(action_type) when is_binary(action_type) do
    action_type |> String.split(" (", parts: 2) |> hd() |> String.trim()
  end

  def verb_of(_), do: "act"

  defp persona_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp persona_name(_persona), do: nil

  defp named(theme, %{"name" => name} = character) when is_binary(name) and name != "",
    do: Archetype.display_name(theme, character)

  defp named(_theme, _character), do: nil
end
