defmodule BotArmyRpg.CampaignRosterStore do
  @moduledoc "In-memory + Ecto store for campaign party rosters."
  use GenServer
  require Logger
  alias BotArmyRpg.Repo
  alias BotArmyRpg.Schemas.CampaignRoster

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    rosters =
      try do
        Repo.all(CampaignRoster)
      rescue
        _ -> []
      end

    state = rosters |> Enum.map(&schema_to_map/1) |> index_by_campaign()
    {:ok, state}
  end

  def handle_get_roster(rpg_campaign_id) do
    GenServer.call(__MODULE__, {:get_roster, rpg_campaign_id})
  end

  def handle_upsert(rpg_campaign_id, npc_slug, attrs) do
    GenServer.call(__MODULE__, {:upsert, rpg_campaign_id, npc_slug, attrs})
  end

  def handle_call({:get_roster, rpg_campaign_id}, _from, state) do
    roster = Map.get(state, rpg_campaign_id, [])
    {:reply, roster, state}
  end

  def handle_call({:upsert, rpg_campaign_id, npc_slug, attrs}, _from, state) do
    existing =
      Repo.get_by(CampaignRoster,
        rpg_campaign_id: rpg_campaign_id,
        npc_slug: npc_slug
      )

    case existing do
      nil ->
        full_attrs =
          attrs |> Map.put("rpg_campaign_id", rpg_campaign_id) |> Map.put("npc_slug", npc_slug)

        case Repo.insert(CampaignRoster.changeset(%CampaignRoster{}, full_attrs)) do
          {:ok, roster} ->
            map = schema_to_map(roster)
            new_state = update_roster_in_state(state, rpg_campaign_id, map, :insert)
            {:reply, {:ok, map}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      roster ->
        case Repo.update(CampaignRoster.changeset(roster, attrs)) do
          {:ok, updated} ->
            map = schema_to_map(updated)
            new_state = update_roster_in_state(state, rpg_campaign_id, map, :update)
            {:reply, {:ok, map}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  defp index_by_campaign(rosters) do
    rosters
    |> Enum.reduce(%{}, fn roster, acc ->
      campaign_id = roster["rpg_campaign_id"]
      Map.update(acc, campaign_id, [roster], fn list -> list ++ [roster] end)
    end)
  end

  defp update_roster_in_state(state, campaign_id, roster_map, :insert) do
    Map.update(state, campaign_id, [roster_map], fn rosters ->
      rosters ++ [roster_map]
    end)
  end

  defp update_roster_in_state(state, campaign_id, roster_map, :update) do
    Map.update(state, campaign_id, [roster_map], fn rosters ->
      rosters
      |> Enum.reject(&(&1["npc_slug"] == roster_map["npc_slug"]))
      |> Kernel.++([roster_map])
    end)
  end

  defp schema_to_map(%CampaignRoster{} = roster) do
    %{
      "id" => roster.id,
      "rpg_campaign_id" => roster.rpg_campaign_id,
      "npc_slug" => roster.npc_slug,
      "display_name" => roster.display_name,
      "tenant_id" => roster.tenant_id,
      "joined_at" => roster.joined_at,
      "left_at" => roster.left_at,
      "inserted_at" => roster.inserted_at,
      "updated_at" => roster.updated_at
    }
  end
end
