defmodule BotArmyRpg.Handlers.PartyHandler do
  @moduledoc """
  Handles party-related NATS requests.

  Routes:
  - rpg.party.get — Get the user's party and companion roster
  - rpg.party.add — Add a bot companion to the party
  - rpg.party.remove — Remove a companion from the party
  - rpg.party.auto_populate — Auto-add all known bots as companions
  """

  require Logger

  alias BotArmyRpg.PartyStore

  def handle_get(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")

    if user_id do
      case PartyStore.get_party(tenant_id, user_id) do
        {:ok, party} ->
          {:ok, enrich_party(party, tenant_id)}

        {:error, :not_found} ->
          {:ok,
           %{
             "name" => "The Adventuring Party",
             "members" => [],
             "message" =>
               "No party yet. Use rpg.party.auto_populate to recruit your bot companions."
           }}
      end
    else
      {:error, :missing_user_id}
    end
  end

  def handle_add(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")
    bot_id = Map.get(message, "bot_id")

    cond do
      is_nil(user_id) ->
        {:error, :missing_user_id}

      is_nil(bot_id) ->
        {:error, :missing_bot_id}

      true ->
        case BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id) do
          {:ok, character} ->
            member_data = %{
              "character_id" => character["id"],
              "bot_id" => bot_id,
              "name" => character["name"],
              "class" => character["class"],
              "race" => character["race"],
              "level" => character["level"]
            }

            case PartyStore.add_member(tenant_id, user_id, member_data) do
              {:ok, party} -> {:ok, enrich_party(party, tenant_id)}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, {:bot_character_failed, reason}}
        end
    end
  end

  def handle_remove(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")
    character_id = Map.get(message, "character_id")

    cond do
      is_nil(user_id) -> {:error, :missing_user_id}
      is_nil(character_id) -> {:error, :missing_character_id}
      true -> PartyStore.remove_member(tenant_id, user_id, character_id)
    end
  end

  def handle_auto_populate(message) do
    tenant_id = Map.get(message, "tenant_id") || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(message, "user_id")

    if user_id do
      case PartyStore.auto_populate(tenant_id, user_id) do
        {:ok, party} ->
          Logger.info(
            "[PartyHandler] Auto-populated party for #{user_id}: #{length(party["members"])} companions"
          )

          {:ok, enrich_party(party, tenant_id)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_user_id}
    end
  end

  defp enrich_party(party, tenant_id) do
    store = Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)

    enriched_members =
      Enum.map(party["members"], fn member ->
        case store.get_by_bot_id(tenant_id, member["bot_id"]) do
          {:ok, character} ->
            member
            |> Map.put("level", character["level"])
            |> Map.put("name", character["name"])
            |> Map.put("stats", character["stats"])

          _ ->
            member
        end
      end)

    Map.put(party, "members", enriched_members)
  end
end
