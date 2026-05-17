defmodule BotArmyRpg.QuestStore do
  @moduledoc """
  In-memory quest store with database persistence.

  Quests are keyed by character_id -> quest_id.
  Status tracking: active, in_progress, completed, abandoned.
  """

  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def create(character_id, quest_data) when is_binary(character_id) and is_map(quest_data) do
    GenServer.call(@server, {:create, character_id, quest_data})
  end

  def get(character_id, quest_id) when is_binary(character_id) and is_binary(quest_id) do
    GenServer.call(@server, {:get, character_id, quest_id})
  end

  def list_active(character_id) when is_binary(character_id) do
    GenServer.call(@server, {:list_active, character_id})
  end

  def list_all(character_id) when is_binary(character_id) do
    GenServer.call(@server, {:list_all, character_id})
  end

  def update(character_id, quest_id, updates) when is_map(updates) do
    GenServer.call(@server, {:update, character_id, quest_id, updates})
  end

  def find_by_gtd_id(character_id, gtd_id) when is_binary(character_id) and is_binary(gtd_id) do
    GenServer.call(@server, {:find_by_gtd_id, character_id, gtd_id})
  end

  def list_completed_by_category(tenant_id, category, limit \\ 10) when is_binary(tenant_id) do
    import Ecto.Query

    BotArmyRpg.Repo.all(
      from(q in BotArmyRpg.Schemas.Quest,
        where:
          q.tenant_id == ^tenant_id and q.source_category == ^category and
            q.status == "completed" and not is_nil(q.outcome_score),
        order_by: [desc: q.inserted_at],
        limit: ^limit,
        select: %{
          id: q.id,
          outcome_score: q.outcome_score,
          success_band: q.success_band,
          inserted_at: q.inserted_at
        }
      )
    )
  rescue
    _ -> []
  end

  @impl true
  def init(_opts) do
    Logger.info("[QuestStore] Starting")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create, character_id, quest_data}, _from, state) do
    quest_id = Map.get(quest_data, "id", Ecto.UUID.generate())

    key = {character_id, quest_id}
    quest = Map.put(quest_data, "id", quest_id)

    new_state = Map.put(state, key, quest)

    Logger.info("[QuestStore] Created quest #{quest_id} for character #{character_id}")
    {:reply, {:ok, quest}, new_state}
  end

  @impl true
  def handle_call({:get, character_id, quest_id}, _from, state) do
    key = {character_id, quest_id}

    case Map.get(state, key) do
      nil -> {:reply, {:error, :not_found}, state}
      quest -> {:reply, {:ok, quest}, state}
    end
  end

  @impl true
  def handle_call({:list_active, character_id}, _from, state) do
    quests =
      state
      |> Enum.filter(fn {{cid, _qid}, quest} ->
        cid == character_id and Map.get(quest, "status") == "active"
      end)
      |> Enum.map(fn {_, quest} -> quest end)

    {:reply, {:ok, quests}, state}
  end

  @impl true
  def handle_call({:list_all, character_id}, _from, state) do
    quests =
      state
      |> Enum.filter(fn {{cid, _qid}, _quest} -> cid == character_id end)
      |> Enum.map(fn {_, quest} -> quest end)

    {:reply, {:ok, quests}, state}
  end

  @impl true
  def handle_call({:find_by_gtd_id, character_id, gtd_id}, _from, state) do
    quest =
      state
      |> Enum.find(fn {{cid, _qid}, quest} ->
        cid == character_id and Map.get(quest, "linked_gtd_id") == gtd_id
      end)

    case quest do
      nil -> {:reply, {:error, :not_found}, state}
      {_key, q} -> {:reply, {:ok, q}, state}
    end
  end

  @impl true
  def handle_call({:update, character_id, quest_id, updates}, _from, state) do
    key = {character_id, quest_id}

    case Map.get(state, key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      quest ->
        updated_quest = Map.merge(quest, updates)
        new_state = Map.put(state, key, updated_quest)
        Logger.info("[QuestStore] Updated quest #{quest_id}")
        {:reply, {:ok, updated_quest}, new_state}
    end
  end
end
