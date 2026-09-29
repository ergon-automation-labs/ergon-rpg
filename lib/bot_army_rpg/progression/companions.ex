defmodule BotArmyRpg.Progression.Companions do
  @moduledoc """
  The other track: the companions level while you are away.

  Persona's reading, and the one asked for here: whoever did the real-world thing earns the
  full award, and every other character of the same household earns a reduced share of it.
  They keep growing between adventures - just not as fast. XP only: the loot still belongs to
  whoever was actually there.

  The rate is a knob (`:away_xp_rate`, default 0.5) and it is validated into
  `[0, 1)` so that an away share can never out-pace the award it shadows.
  """

  require Logger

  # Aliased deliberately: inside BotArmyRpg.Progression an unqualified CharacterStore would
  # be read as BotArmyRpg.Progression.CharacterStore.
  alias BotArmyRpg.CharacterStore
  alias BotArmyRpg.NATS.Publisher

  @default_rate 0.5
  @away_subject "rpg.progression.away"

  @doc "How much of an award a companion earns. An unusable setting falls back, loudly."
  def away_rate do
    case Application.get_env(:bot_army_rpg, :away_xp_rate, @default_rate) do
      rate when is_number(rate) and rate >= 0 and rate < 1 ->
        rate

      unusable ->
        Logger.warning(
          "[Companions] Ignoring unusable away_xp_rate #{inspect(unusable)}; using #{@default_rate}"
        )

        @default_rate
    end
  end

  @doc "One companion's share of an award, at the configured rate."
  def share(xp_amount), do: share(xp_amount, away_rate())

  @doc "One companion's share of an award, at `rate`. Nothing earns nothing."
  def share(xp_amount, rate) when is_integer(xp_amount) and xp_amount > 0 and is_number(rate),
    do: trunc(xp_amount * rate)

  def share(_xp_amount, _rate), do: 0

  @doc "Everyone in the household except the character who was actually there."
  def targets(characters, participant) when is_list(characters),
    do: Enum.reject(characters, &(&1["id"] == participant["id"]))

  @doc """
  Award the away share to every companion of `participant`.

  Never raises, never exits, and never touches the participant's own award: a companion the
  store cannot find is logged and skipped, and a store that is down leaves the rest of the
  progression alone. Returns the characters that were awarded, or `0` when the share rounds
  away to nothing - in which case the store is not called at all.
  """
  def award_away(tenant_id, participant, xp_amount, opts \\ []) do
    rate = Keyword.get(opts, :rate, away_rate())
    announce = Keyword.get(opts, :publish, &announce_away/2)
    store = Keyword.get(opts, :store, store())

    with share when share > 0 <- share(xp_amount, rate) do
      tenant_id
      |> characters(store)
      |> targets(participant)
      |> Enum.flat_map(&award_one(store, tenant_id, &1, share, announce))
    end
  rescue
    e ->
      # The struct AND its message: an exception message is short by construction, and a
      # rescue that logs only "ArgumentError" cannot be diagnosed. (Exit reasons are handled
      # below and are never inspected wholesale - they embed the call they came from.)
      Logger.error(
        "[Companions] Away award failed: #{inspect(e.__struct__)} - #{Exception.message(e)}"
      )

      []
  catch
    :exit, reason ->
      Logger.error("[Companions] Away award could not reach the store: #{inspect(shape(reason))}")
      []
  end

  defp characters(tenant_id, store) do
    case store.list(tenant_id) do
      {:ok, characters} when is_list(characters) ->
        characters

      refused ->
        Logger.warning("[Companions] Could not list characters: #{inspect(refused)}")
        []
    end
  end

  defp award_one(store, tenant_id, companion, share, announce) do
    case award(store, tenant_id, companion, share) do
      {:ok, updated} ->
        announce.(tenant_id, away_payload(companion, updated, share))
        [updated]

      {:error, reason} ->
        Logger.warning(
          "[Companions] #{companion["name"] || companion["id"]} kept no away XP: " <>
            inspect(shape(reason))
        )

        []
    end
  end

  # A companion is a bot-owned character; a player-owned one still earns, through its user.
  defp award(store, tenant_id, %{"bot_id" => bot_id}, share)
       when is_binary(bot_id) and bot_id != "",
       do: store.award_xp_to_bot(tenant_id, bot_id, share)

  defp award(store, tenant_id, %{"user_id" => user_id}, share)
       when is_binary(user_id) and user_id != "",
       do: store.award_xp(tenant_id, user_id, share)

  defp award(_store, _tenant_id, companion, _share),
    do: {:error, {:not_awardable, companion["id"]}}

  defp away_payload(companion, updated, share) do
    stats = Map.get(updated, "stats", %{})
    old_level = Map.get(companion, "level", 0)
    new_level = Map.get(updated, "level", old_level)

    %{
      "away" => true,
      "character_id" => updated["id"] || companion["id"],
      "character_name" => updated["name"] || companion["name"],
      "xp_earned" => share,
      "xp_current" => Map.get(stats, "xp", 0),
      "xp_to_next" => Map.get(stats, "xp_to_next", 500),
      "level" => new_level,
      "leveled_up" => new_level > old_level,
      "old_level" => old_level
    }
  end

  defp announce_away(tenant_id, payload) do
    Publisher.publish(@away_subject, payload, tenant_id: tenant_id)
  end

  defp store, do: Application.get_env(:bot_army_rpg, :character_store, CharacterStore)

  # The reason's shape, never its arguments: an exit reason embeds the call it came from.
  defp shape(reason) when is_atom(reason), do: reason
  defp shape({reason, _call}) when is_atom(reason), do: reason
  defp shape(reason) when is_tuple(reason), do: elem(reason, 0)
  defp shape(_reason), do: :unknown
end
