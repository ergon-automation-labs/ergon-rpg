defmodule BotArmyRpg.GM.Narrator do
  @moduledoc """
  Builds prompts and calls the LLM bot for GM narration.

  Falls back to template-based narration if the LLM is unavailable.

  When the current theme reskins a bot's archetype (see
  `BotArmyRpg.Themes.Archetype`), the actor's themed identity is woven into
  both the LLM prompt and the fallback prose without mutating the character
  row.
  """

  require Logger

  alias BotArmyRpg.Themes.Archetype

  @llm_timeout_ms 3000
  @circuit_breaker_key "rpg:gm:llm.narrate"

  @doc """
  Narrate a scene using theme vocabulary and templates.

  Returns `{:ok, String.t()}` or `{:error, reason}`.
  """
  def narrate_scene(scene_description, theme, recent_facts) do
    prompt = build_scene_prompt(scene_description, theme, recent_facts)

    case call_llm(prompt) do
      {:ok, text} -> {:ok, text}
      {:error, _} -> {:ok, fallback_scene(scene_description, theme)}
    end
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

  defp build_scene_prompt(scene_description, theme, recent_facts) do
    setting = theme["setting"] || "unknown realm"
    tone = theme["tone"] || "neutral"
    vocab = theme["vocabulary"] || %{}

    facts_text =
      if recent_facts in [nil, []] do
        ""
      else
        "Recent events:\n" <> Enum.join(recent_facts, "\n")
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

  defp call_llm(prompt_text) do
    payload = %{"prompt" => prompt_text}

    case publisher().request("llm.prompt.submit", payload,
           timeout_ms: @llm_timeout_ms,
           circuit_breaker_key: @circuit_breaker_key
         ) do
      {:ok, %{"data" => data}} ->
        {:ok, data["text"] || data["response"] || inspect(data)}

      {:ok, other} ->
        {:ok, inspect(other)}

      {:error, reason} ->
        Logger.warning("[GM.Narrator] LLM narration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end

  # --- Fallbacks ---

  defp fallback_scene(scene_description, theme) do
    setting = theme["setting"] || "this realm"
    tone = theme["tone"] || ""

    desc = scene_description || "An unremarkable location"

    "You find yourself in #{desc}. The air of #{setting} feels #{tone || "heavy"}."
  end

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
