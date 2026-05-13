defmodule BotArmyRpg.Themes.Archetype do
  @moduledoc """
  Theme-aware lookup of bot archetypes for narration.

  Resolves a bot to a themed persona at narration time without mutating the
  character row. When a theme's `npc_personas` declares `bot_assignments`,
  the matching persona is returned; otherwise the canonical race/class
  from `BotArmyRpg.Defaults.bot_archetype/1` is wrapped as a default.

  Switching themes does not lie about character sheets — the sheet keeps
  its canonical race/class, and only the narrator's prose changes.

  ## Return shapes

    * `{:themed, persona_map}` — the active theme reskins this bot. The map
      includes the persona's `"title"`, `"demeanor"`, and any other fields
      from `npc_personas`, plus a `"_persona_key"` for diagnostics.
    * `{:default, %{"title" => "..", "race" => "..", "class" => ".."}}` —
      no themed persona; fell back to `Defaults.bot_archetype/1`.
    * `:no_actor` — no usable `bot_id` on the character / actor.
    * `:no_theme` — theme map was nil or empty.
  """

  alias BotArmyRpg.Defaults

  @doc """
  Resolve an archetype for a bot id under the given theme.
  """
  def for_bot(theme, bot_id)
      when is_map(theme) and (is_binary(bot_id) or is_atom(bot_id)) do
    key = canonical_key(bot_id)
    personas = theme["npc_personas"] || %{}

    case find_persona(personas, key) do
      nil ->
        default_archetype(bot_id)

      {persona_key, persona} ->
        {:themed, Map.put(persona, "_persona_key", persona_key)}
    end
  end

  def for_bot(nil, _bot_id), do: :no_theme
  def for_bot(_, _), do: :no_actor

  @doc """
  Resolve an archetype for a character map (expects `"bot_id"` field).
  """
  def for_character(theme, %{"bot_id" => bot_id})
      when is_binary(bot_id) and bot_id != "" do
    for_bot(theme, bot_id)
  end

  def for_character(_theme, _character), do: :no_actor

  @doc """
  Render a one-line prompt hint for a resolved archetype.

  Returns an empty string when no archetype is available. Safe to splice
  into LLM prompts unconditionally.
  """
  def prompt_hint({:themed, persona}) do
    title = persona["title"] || "Unknown"
    demeanor = persona["demeanor"]

    if is_binary(demeanor) and demeanor != "" do
      "The actor presents as a #{title} — #{demeanor}."
    else
      "The actor presents as a #{title}."
    end
  end

  def prompt_hint({:default, %{"title" => title}}) when is_binary(title) do
    "The actor is a #{title}."
  end

  def prompt_hint(_), do: ""

  @doc """
  Render a short narrative label for fallback prose (no LLM available).

  Returns the themed title when one is available, otherwise the character's
  given name, otherwise a generic fallback.
  """
  def display_label(archetype, character_name \\ nil)

  def display_label({:themed, persona}, _), do: "the " <> (persona["title"] || "stranger")

  def display_label({:default, _}, name) when is_binary(name) and name != "", do: name
  def display_label({:default, %{"title" => title}}, _), do: title

  def display_label(_, name) when is_binary(name) and name != "", do: name
  def display_label(_, _), do: "the character"

  defp find_persona(personas, bot_key) do
    Enum.find_value(personas, fn
      {persona_key, %{} = persona} ->
        assignments = persona |> Map.get("bot_assignments", []) |> List.wrap()

        if bot_key in assignments do
          {persona_key, persona}
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp canonical_key(bot_id) do
    bot_id
    |> to_string()
    |> String.downcase()
    |> String.replace_prefix("bot_army_", "")
  end

  defp default_archetype(bot_id) do
    arch = Defaults.bot_archetype(bot_id)
    title = "#{arch.race} #{arch.class}"

    {:default,
     %{
       "title" => title,
       "race" => arch.race,
       "class" => arch.class
     }}
  end
end
