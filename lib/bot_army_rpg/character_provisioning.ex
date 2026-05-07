defmodule BotArmyRpg.CharacterProvisioning do
  @moduledoc """
  Auto-provisions RPG characters for bots by bridging Soul -> Character.

  Each bot in the Bot Army can have its own persistent RPG character sheet.
  This module checks if a character exists for a given bot_id; if not,
  it creates one using the bot's Soul config and default archetypes.
  """

  require Logger

  alias BotArmyRuntime.Personality.ThemeConfig

  @doc """
  Ensure a bot has an RPG character. Creates one if missing.

  Returns `{:ok, character}` or `{:error, reason}`.
  """
  @spec ensure_bot_character(String.t() | atom(), String.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def ensure_bot_character(bot_id, tenant_id \\ nil) do
    tenant_id = tenant_id || BotArmyRuntime.Tenant.default_tenant_id()
    bot_id_str = normalize_bot_id(bot_id)

    store = Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)

    case store.get_by_bot_id(tenant_id, bot_id_str) do
      {:ok, character} ->
        {:ok, character}

      {:error, :not_found} ->
        create_bot_character(bot_id_str, tenant_id, store)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the character for a bot, returning nil if none exists.
  """
  @spec get_bot_character(String.t() | atom(), String.t() | nil) :: map() | nil
  def get_bot_character(bot_id, tenant_id \\ nil) do
    tenant_id = tenant_id || BotArmyRuntime.Tenant.default_tenant_id()
    bot_id_str = normalize_bot_id(bot_id)

    store = Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)

    case store.get_by_bot_id(tenant_id, bot_id_str) do
      {:ok, character} -> character
      _ -> nil
    end
  end

  @doc """
  Build a character name from the bot's Soul config and theme persona.

  Prefers the RPG persona name from ThemeConfig, then Soul identity name,
  then a sanitized bot_id.
  """
  @spec bot_character_name(String.t(), ThemeConfig.t() | nil) :: String.t()
  def bot_character_name(bot_id, theme \\ nil) do
    bot_id_str = normalize_bot_id(bot_id)

    # 1. Try theme persona name
    theme_name =
      if theme do
        case Map.get(theme.npc_personas, bot_id_str) do
          %{name: name} -> name
          _ -> nil
        end
      else
        nil
      end

    # 2. Try Soul identity name (graceful if repo is unavailable)
    soul_name =
      try do
        case BotArmy.Soul.get(String.to_atom(bot_id_str)) do
          nil -> nil
          soul -> get_in(soul.config, ["identity", "name"])
        end
      rescue
        _ -> nil
      end

    # 3. Fallback to sanitized bot_id
    fallback =
      bot_id_str
      |> String.replace_prefix("bot_army_", "")
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    theme_name || soul_name || fallback
  end

  defp create_bot_character(bot_id_str, tenant_id, store) do
    archetype = BotArmyRpg.Defaults.bot_archetype(bot_id_str)
    theme = ThemeConfig.fantasy()
    name = bot_character_name(bot_id_str, theme)
    play_style = bot_play_style(bot_id_str)
    stats = default_stats_for_theme(tenant_id)

    notes =
      if play_style do
        "Auto-provisioned character for #{bot_id_str}. play_style: #{play_style}."
      else
        "Auto-provisioned character for #{bot_id_str}."
      end

    payload = %{
      "name" => name,
      "race" => archetype.race,
      "class" => archetype.class,
      "level" => 1,
      "stats" => stats,
      "inventory" => BotArmyRpg.Defaults.default_inventory(),
      "tenant_id" => tenant_id,
      "bot_id" => bot_id_str,
      "notes" => notes
    }

    case store.create(payload) do
      {:ok, character} = result ->
        Logger.info(
          "[CharacterProvisioning] Created character for #{bot_id_str}: #{character["id"]}"
        )

        result

      {:error, reason} = err ->
        Logger.error("[CharacterProvisioning] Failed for #{bot_id_str}: #{inspect(reason)}")
        err
    end
  end

  defp default_stats_for_theme(tenant_id) do
    theme_store = Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)

    case theme_store.get_current(tenant_id) do
      {:ok, theme} ->
        setting = theme["setting"] || ""

        if String.contains?(String.downcase(setting), "cyberpunk") do
          BotArmyRpg.Defaults.default_cyberpunk_stats()
        else
          BotArmyRpg.Defaults.default_pathfinder_stats()
        end

      _ ->
        BotArmyRpg.Defaults.default_pathfinder_stats()
    end
  end

  @doc """
  Read optional play_style from Soul config for a bot.
  Returns a string like "aggressive", "supportive", "tactical", or nil.
  """
  def bot_play_style(bot_id) do
    bot_id_str = normalize_bot_id(bot_id)

    try do
      case BotArmy.Soul.get(String.to_atom(bot_id_str)) do
        nil -> nil
        soul -> get_in(soul.config, ["play_style", "strategy"])
      end
    rescue
      _ -> nil
    end
  end

  defp normalize_bot_id(bot_id) when is_binary(bot_id), do: bot_id
  defp normalize_bot_id(bot_id) when is_atom(bot_id), do: Atom.to_string(bot_id)
  defp normalize_bot_id(bot_id), do: to_string(bot_id)
end
