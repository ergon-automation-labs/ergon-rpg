defmodule BotArmyRpg.Handlers.PartyHandler do
  @moduledoc """
  Handles party NATS requests.

  Routes:

  - `rpg.party.get` — the party and its companion roster
  - `rpg.party.add` — recruit a bot companion into the party
  - `rpg.party.remove` — take a companion out of the party
  - `rpg.party.set_narrator` — name one member the party's narrator (`null` clears it)

  `rpg.party.auto_populate` is implemented here but deliberately **not** registered.
  The list of bot ids it recruits from is a hardcoded guess (`gtd`, `llm`) that does
  not match the characters the fleet actually has (`gtd_bot`, `llm_bot`), so a
  registered `auto_populate` would create a parallel ghost of every companion. See
  the note in `BotArmyRpg.NATS.Consumer`, where it would be registered.

  That is also why "no party yet" no longer sends a caller to it: this handler used to
  answer with a route nobody answers (`Use rpg.party.auto_populate ...`), which read as
  an instruction and was a dead end. The way out it names is now `rpg.party.add`, the
  recruitment route that is actually registered (pinned by a test that checks the named
  subject against `BotArmyRpg.NATS.Consumer.subjects/0`).

  The store is read through `party_store/0` and never by naming `PartyStore` directly:
  the two are different questions — *which store* and *is there one* — and a handler
  that hardcodes the second cannot be tested with the first (the party routes answered
  from the real store even when a test had pointed the app at a stand-in).
  """

  require Logger

  @no_party_message "No party yet. Use rpg.party.add to recruit a bot companion."

  defp party_store do
    Application.get_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_get(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")

    with :ok <- require_user(user_id) do
      case party_store().get_party(tenant_id, user_id) do
        {:ok, party} ->
          {:ok, enrich_party(party, tenant_id)}

        {:error, :not_found} ->
          # "No party yet" is a fact and is said out loud; it is not an empty party
          # handed over as if it were the party. The party's name comes from the store
          # so it is written once.
          {:ok, Map.put(BotArmyRpg.PartyStore.blank_party(), "message", @no_party_message)}

        {:error, reason} ->
          # A party that could not be read is a refusal. Answering with an empty party
          # would report "nobody is with you" about a party nobody managed to read.
          {:error, reason}
      end
    end
  end

  def handle_add(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")
    bot_id = Map.get(message, "bot_id")

    with :ok <- require_user(user_id),
         :ok <- require_bot(bot_id),
         {:ok, character} <- fetch_bot_character(bot_id, tenant_id) do
      member_data = %{
        "character_id" => character["id"],
        "bot_id" => bot_id,
        "name" => character["name"],
        "class" => character["class"],
        "race" => character["race"],
        "level" => character["level"]
      }

      case party_store().add_member(tenant_id, user_id, member_data) do
        {:ok, party} -> {:ok, enrich_party(party, tenant_id)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp require_user(nil), do: {:error, :missing_user_id}
  defp require_user(_user_id), do: :ok

  defp require_bot(nil), do: {:error, :missing_bot_id}
  defp require_bot(_bot_id), do: :ok

  defp fetch_bot_character(bot_id, tenant_id) do
    case BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id) do
      {:ok, character} -> {:ok, character}
      {:error, reason} -> {:error, {:bot_character_failed, reason}}
    end
  end

  def handle_remove(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")
    character_id = Map.get(message, "character_id")

    cond do
      is_nil(user_id) -> {:error, :missing_user_id}
      is_nil(character_id) -> {:error, :missing_character_id}
      true -> party_store().remove_member(tenant_id, user_id, character_id)
    end
  end

  # Naming the narrator is a write, and the store answers it with the party read back
  # after the rows moved — so a caller is never handed the party its request implied.
  #
  # An absent `character_id` and an explicit `null` are different requests: the first is a
  # caller who forgot to name anyone (`:missing_character_id`), the second is how the role
  # is cleared. A member the party does not have is `:not_a_member` (the store refuses it),
  # never a quiet promotion of nobody.
  def handle_set_narrator(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")

    cond do
      is_nil(user_id) -> {:error, :missing_user_id}
      not Map.has_key?(message, "character_id") -> {:error, :missing_character_id}
      true -> name_narrator(tenant_id, user_id, Map.get(message, "character_id"))
    end
  end

  defp name_narrator(tenant_id, user_id, character_id) do
    case party_store().set_narrator(tenant_id, user_id, character_id) do
      {:ok, party} -> {:ok, enrich_party(party, tenant_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_auto_populate(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")

    if user_id do
      case party_store().auto_populate(tenant_id, user_id) do
        {:ok, party} ->
          Logger.info(
            "[PartyHandler] Auto-populated party for #{user_id}: #{length(party["members"] || [])} companions"
          )

          {:ok, enrich_party(party, tenant_id)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_user_id}
    end
  end

  # The party, with each member's live name, level and stats where the character store
  # can vouch for them. A member whose character cannot be read is *kept*, under the
  # name the party already has: dropping them would report a party of four as a party
  # of three, which is a reading nobody took.
  defp enrich_party(party, tenant_id) do
    members = party["members"] || []
    Map.put(party, "members", Enum.map(members, &enrich_member(&1, tenant_id)))
  end

  defp enrich_member(member, tenant_id) do
    bot_id = member["bot_id"]

    if is_binary(bot_id) and bot_id != "" do
      case character_store().get_by_bot_id(tenant_id, bot_id) do
        {:ok, character} ->
          member
          |> Map.put("level", character["level"])
          |> Map.put("name", character["name"])
          |> Map.put("stats", character["stats"])

        _ ->
          member
      end
    else
      member
    end
  end
end
