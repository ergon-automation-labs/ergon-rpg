defmodule BotArmyRpg.DailyNarrator do
  @moduledoc """
  Generates daily narrative updates based on character progression.

  Runs once per day, checks for recent level-ups and loot acquisition,
  generates flavor-text story scenes via LLM, publishes to Discord.
  """

  use GenServer
  require Logger

  @server __MODULE__
  # 1 hour checks for daily quota
  @check_interval_ms 3_600_000
  # 9 AM daily
  @narrative_update_hour 9

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @impl true
  def init(opts) do
    Logger.info("[DailyNarrator] Starting")
    schedule_next_check()
    {:ok, %{opts: opts}}
  end

  @impl true
  def handle_info(:check_daily, state) do
    if should_generate_narrative?() do
      generate_and_publish_narratives()
    end

    schedule_next_check()
    {:noreply, state}
  end

  defp schedule_next_check do
    Process.send_after(self(), :check_daily, @check_interval_ms)
  end

  defp should_generate_narrative? do
    now = DateTime.utc_now()
    now.hour == @narrative_update_hour and not already_generated_today?()
  end

  defp already_generated_today? do
    # In production, this would check Redis or a generated_narratives table
    # For now, always return false to generate on schedule
    false
  end

  defp generate_and_publish_narratives do
    case get_active_characters() do
      {:ok, characters} ->
        characters
        |> Enum.filter(&has_recent_progression?/1)
        |> Enum.each(&generate_narrative_for_character/1)

      {:error, reason} ->
        Logger.warning("[DailyNarrator] Failed to fetch characters: #{inspect(reason)}")
    end
  end

  defp get_active_characters do
    try do
      characters = BotArmyRpg.CharacterStore.list("default")
      characters
    rescue
      _ -> {:error, :database_error}
    end
  end

  defp has_recent_progression?(character) do
    stats = Map.get(character, "stats", %{})
    xp = Map.get(stats, "xp", 0)
    level = Map.get(character, "level", 1)

    # Simple heuristic: has XP or is above level 1
    xp > 0 or level > 1
  end

  defp generate_narrative_for_character(character) do
    character_id = Map.get(character, "id")
    name = Map.get(character, "name", "Unknown")
    class = Map.get(character, "class", "Adventurer")
    level = Map.get(character, "level", 1)
    stats = Map.get(character, "stats", %{})
    xp = Map.get(stats, "xp", 0)
    inventory = Map.get(character, "inventory", %{})
    items = Map.get(inventory, "items", [])

    prompt =
      build_narrative_prompt(name, class, level, xp, Enum.count(items))

    case request_narrative(prompt) do
      {:ok, narrative} ->
        publish_narrative(character_id, narrative)
        Logger.info("[DailyNarrator] Generated narrative for #{name} (#{character_id})")

      {:error, reason} ->
        Logger.warning(
          "[DailyNarrator] Failed to generate narrative for #{name}: #{inspect(reason)}"
        )
    end
  end

  defp build_narrative_prompt(name, class, level, xp, item_count) do
    """
    Write a brief, atmospheric 2-3 sentence story snippet about #{name}, a #{class} of level #{level}.

    Context: They have accumulated #{xp} experience points and acquired #{item_count} items on their journey.

    Style: Evocative, second-person perspective, set in a fantasy tavern. No dialogue. Focus on atmosphere and their accomplishments.

    Example: "The tavern falls quiet as you stride in, your gear jingling with the weight of recent conquests. Firelight catches the new enchantments adorning your armor..."

    Generate a unique snippet for this character.
    """
  end

  defp request_narrative(prompt) do
    payload =
      Jason.encode!(%{
        "text" => prompt,
        "model" => "claude-opus",
        "max_tokens" => 150,
        "prompt_id" => UUID.uuid4(),
        "source" => "rpg_daily_narrator"
      })

    case Gnat.request(
           :nats_connection,
           "llm.prompt.submit",
           payload,
           receive_timeout: 15_000
         ) do
      {:ok, response} ->
        body =
          case response do
            %{body: body} -> body
            body when is_binary(body) -> body
          end

        with {:ok, decoded} <- Jason.decode(body),
             text <- Map.get(decoded, "text", "") do
          {:ok, text}
        else
          _ -> {:error, :decode_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publish_narrative(character_id, narrative) do
    payload =
      Jason.encode!(%{
        "character_id" => character_id,
        "narrative" => narrative,
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Publish as event for Discord subscriptions
    BotArmyRpg.NATS.Publisher.publish(
      "rpg.narrative.daily",
      Jason.decode!(payload),
      tenant_id: "default"
    )
  end
end
