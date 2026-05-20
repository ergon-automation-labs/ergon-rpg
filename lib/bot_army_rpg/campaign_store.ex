defmodule BotArmyRpg.CampaignStore do
  @moduledoc "In-memory + Ecto store for TTRPG campaign metadata and state."
  use GenServer
  require Logger
  alias BotArmyRpg.Repo
  alias BotArmyRpg.Schemas.Campaign

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    campaigns =
      try do
        Repo.all(Campaign)
      rescue
        _ -> []
      end

    state = campaigns |> Enum.map(&schema_to_map/1) |> index_by_project_and_id()
    {:ok, state}
  end

  def handle_insert(attrs) do
    GenServer.call(__MODULE__, {:insert, attrs})
  end

  def handle_get_by_project(gtd_project_id) do
    GenServer.call(__MODULE__, {:get_by_project, gtd_project_id})
  end

  def handle_get_by_id(rpg_campaign_id) do
    GenServer.call(__MODULE__, {:get_by_id, rpg_campaign_id})
  end

  def handle_update(rpg_campaign_id, attrs) do
    GenServer.call(__MODULE__, {:update, rpg_campaign_id, attrs})
  end

  def handle_list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  def handle_call({:insert, attrs}, _from, state) do
    case Repo.insert(Campaign.changeset(%Campaign{}, attrs)) do
      {:ok, campaign} ->
        map = schema_to_map(campaign)
        new_state = state |> Map.put(campaign.gtd_project_id, map) |> Map.put(campaign.id, map)
        {:reply, {:ok, map}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_by_project, gtd_project_id}, _from, state) do
    result = Map.get(state, gtd_project_id)
    {:reply, result, state}
  end

  def handle_call({:get_by_id, rpg_campaign_id}, _from, state) do
    result = Map.get(state, rpg_campaign_id)
    {:reply, result, state}
  end

  def handle_call({:update, rpg_campaign_id, attrs}, _from, state) do
    case Repo.get(Campaign, rpg_campaign_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      campaign ->
        case Repo.update(Campaign.changeset(campaign, attrs)) do
          {:ok, updated} ->
            map = schema_to_map(updated)
            new_state = state |> Map.put(updated.gtd_project_id, map) |> Map.put(updated.id, map)
            {:reply, {:ok, map}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:list_active, _from, state) do
    active =
      state
      |> Map.values()
      |> Enum.uniq_by(& &1["id"])
      |> Enum.filter(&(&1["status"] == "active"))

    {:reply, active, state}
  end

  defp index_by_project_and_id(campaigns) do
    campaigns
    |> Enum.reduce(%{}, fn campaign, acc ->
      acc
      |> Map.put(campaign["gtd_project_id"], campaign)
      |> Map.put(campaign["id"], campaign)
    end)
  end

  defp schema_to_map(%Campaign{} = campaign) do
    %{
      "id" => campaign.id,
      "tenant_id" => campaign.tenant_id,
      "gtd_project_id" => campaign.gtd_project_id,
      "theme_snapshot" => campaign.theme_snapshot,
      "status" => campaign.status,
      "started_at" => campaign.started_at,
      "ended_at" => campaign.ended_at,
      "inserted_at" => campaign.inserted_at,
      "updated_at" => campaign.updated_at
    }
  end
end
