defmodule BotArmyRpg.XpEventStore do
  use GenServer
  require Logger
  alias BotArmyRpg.Repo
  alias BotArmyRpg.Schemas.XpEvent

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    events =
      try do
        Repo.all(XpEvent)
      rescue
        _ -> []
      end

    state = events |> Enum.map(&schema_to_map/1) |> index_by_campaign()
    {:ok, state}
  end

  def handle_insert(attrs) do
    GenServer.call(__MODULE__, {:insert, attrs})
  end

  def handle_get_events(rpg_campaign_id, filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_events, rpg_campaign_id, filters})
  end

  def handle_call({:insert, attrs}, _from, state) do
    case Repo.insert(XpEvent.changeset(%XpEvent{}, attrs)) do
      {:ok, event} ->
        map = schema_to_map(event)
        campaign_id = event.rpg_campaign_id

        new_state =
          Map.update(state, campaign_id, [map], fn events ->
            events ++ [map]
          end)

        {:reply, {:ok, map}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_events, rpg_campaign_id, filters}, _from, state) do
    events = Map.get(state, rpg_campaign_id, [])

    filtered =
      events
      |> filter_by_actor_kind(Map.get(filters, :actor_kind))
      |> filter_by_actor_id(Map.get(filters, :actor_id))

    {:reply, filtered, state}
  end

  defp index_by_campaign(events) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      campaign_id = event["rpg_campaign_id"]
      Map.update(acc, campaign_id, [event], fn list -> list ++ [event] end)
    end)
  end

  defp filter_by_actor_kind(events, nil), do: events
  defp filter_by_actor_kind(events, kind), do: Enum.filter(events, &(&1["actor_kind"] == kind))

  defp filter_by_actor_id(events, nil), do: events
  defp filter_by_actor_id(events, id), do: Enum.filter(events, &(&1["actor_id"] == id))

  defp schema_to_map(%XpEvent{} = event) do
    %{
      "id" => event.id,
      "rpg_campaign_id" => event.rpg_campaign_id,
      "actor_kind" => event.actor_kind,
      "actor_id" => event.actor_id,
      "delta" => event.delta,
      "reason_code" => event.reason_code,
      "tenant_id" => event.tenant_id,
      "inserted_at" => event.inserted_at,
      "updated_at" => event.updated_at
    }
  end
end
