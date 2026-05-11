defmodule BotArmyRpg.PartyStore do
  @moduledoc """
  In-memory party store tracking bot companion membership per user.

  A party persists across RPG sessions — it's the user's permanent adventuring
  group of bot companions. Each bot that does real work (completes tasks, logs
  workouts, etc.) is a party member that earns XP alongside the user.

  State: %{{tenant_id, user_id} => party_map}
  """

  @behaviour BotArmyRpg.PartyStoreBehaviour

  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @impl true
  def get_party(tenant_id, user_id) when is_binary(tenant_id) and is_binary(user_id) do
    GenServer.call(@server, {:get_party, tenant_id, user_id})
  end

  def add_member(tenant_id, user_id, member_data) when is_map(member_data) do
    GenServer.call(@server, {:add_member, tenant_id, user_id, member_data})
  end

  def remove_member(tenant_id, user_id, character_id) when is_binary(character_id) do
    GenServer.call(@server, {:remove_member, tenant_id, user_id, character_id})
  end

  def auto_populate(tenant_id, user_id) when is_binary(tenant_id) and is_binary(user_id) do
    GenServer.call(@server, {:auto_populate, tenant_id, user_id}, 15_000)
  end

  @impl true
  def list_parties(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list_parties, tenant_id})
  end

  @impl true
  def init(_opts) do
    Logger.info("[PartyStore] Starting")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_party, tenant_id, user_id}, _from, state) do
    key = {tenant_id, user_id}

    case Map.get(state, key) do
      nil -> {:reply, {:error, :not_found}, state}
      party -> {:reply, {:ok, party}, state}
    end
  end

  @impl true
  def handle_call({:add_member, tenant_id, user_id, member_data}, _from, state) do
    key = {tenant_id, user_id}
    party = Map.get(state, key, new_party())

    character_id = member_data["character_id"]
    already_member = Enum.any?(party["members"], &(&1["character_id"] == character_id))

    if already_member do
      {:reply, {:ok, party}, state}
    else
      member = %{
        "character_id" => character_id,
        "bot_id" => member_data["bot_id"],
        "name" => member_data["name"],
        "class" => member_data["class"],
        "race" => member_data["race"],
        "level" => member_data["level"] || 1,
        "role" => member_data["role"] || "companion",
        "joined_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      updated_party = Map.update!(party, "members", &[member | &1])
      new_state = Map.put(state, key, updated_party)

      Logger.info("[PartyStore] #{member["name"]} (#{member["class"]}) joined #{user_id}'s party")

      {:reply, {:ok, updated_party}, new_state}
    end
  end

  @impl true
  def handle_call({:remove_member, tenant_id, user_id, character_id}, _from, state) do
    key = {tenant_id, user_id}

    case Map.get(state, key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      party ->
        updated_members =
          Enum.reject(party["members"], &(&1["character_id"] == character_id))

        updated_party = Map.put(party, "members", updated_members)
        new_state = Map.put(state, key, updated_party)

        Logger.info("[PartyStore] Removed #{character_id} from #{user_id}'s party")
        {:reply, {:ok, updated_party}, new_state}
    end
  end

  @impl true
  def handle_call({:auto_populate, tenant_id, user_id}, _from, state) do
    key = {tenant_id, user_id}
    party = Map.get(state, key, new_party())

    bot_ids = known_bot_ids()

    {updated_party, count} =
      Enum.reduce(bot_ids, {party, 0}, fn bot_id, {acc_party, acc_count} ->
        already_member =
          Enum.any?(acc_party["members"], &(&1["bot_id"] == bot_id))

        if already_member do
          {acc_party, acc_count}
        else
          case ensure_bot_character(bot_id, tenant_id) do
            {:ok, character} ->
              member = %{
                "character_id" => character["id"],
                "bot_id" => bot_id,
                "name" => character["name"],
                "class" => character["class"],
                "race" => character["race"],
                "level" => character["level"] || 1,
                "role" => "companion",
                "joined_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }

              updated = Map.update!(acc_party, "members", &[member | &1])
              {updated, acc_count + 1}

            {:error, _reason} ->
              {acc_party, acc_count}
          end
        end
      end)

    new_state = Map.put(state, key, updated_party)

    Logger.info(
      "[PartyStore] Auto-populated #{count} companions for #{user_id}'s party (#{length(updated_party["members"])} total)"
    )

    {:reply, {:ok, updated_party}, new_state}
  end

  @impl true
  def handle_call({:list_parties, tenant_id}, _from, state) do
    parties =
      state
      |> Enum.filter(fn {{tid, _uid}, _party} -> tid == tenant_id end)
      |> Enum.map(fn {{_tid, uid}, party} -> Map.put(party, "user_id", uid) end)

    {:reply, {:ok, parties}, state}
  end

  defp new_party do
    %{
      "name" => "The Adventuring Party",
      "members" => [],
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp ensure_bot_character(bot_id, tenant_id) do
    BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id)
  end

  defp known_bot_ids do
    [
      "gtd",
      "synapse",
      "llm",
      "fitness",
      "terrain",
      "chore",
      "job_applications",
      "discord",
      "claude_bridge",
      "database_backups",
      "sre"
    ]
  end
end
