defmodule BotArmyRpg.SceneFactStore do
  @moduledoc "In-memory + Ecto store for scene facts and narrative state."
  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def append(payload) when is_map(payload), do: GenServer.call(@server, {:append, payload})

  def list_for_session(tenant_id, session_id),
    do: GenServer.call(@server, {:list_for_session, tenant_id, session_id})

  def clear, do: GenServer.call(@server, :clear)

  @impl true
  def init(_opts) do
    Logger.info("[SceneFactStore] Starting")

    state =
      try do
        facts = BotArmyRpg.Repo.all(BotArmyRpg.Schemas.SceneFact)

        Enum.reduce(facts, %{}, fn fact, acc ->
          Map.put(acc, fact.id |> to_string(), schema_to_map(fact))
        end)
      rescue
        _ ->
          Logger.warning("[SceneFactStore] Database unavailable, starting empty")
          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:append, payload}, _from, state) do
    fact_id = Ecto.UUID.generate()
    tenant_id = payload["tenant_id"] || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(payload, "user_id")

    changeset =
      BotArmyRpg.Schemas.SceneFact.changeset(
        %BotArmyRpg.Schemas.SceneFact{id: fact_id},
        %{
          "tenant_id" => convert_to_uuid(tenant_id),
          "user_id" => if(user_id, do: convert_to_uuid(user_id), else: nil),
          "session_id" => convert_to_uuid(payload["session_id"]),
          "content" => payload["content"],
          "category" => Map.get(payload, "category", "observation"),
          "source" => Map.get(payload, "source", "gm")
        }
      )

    case BotArmyRpg.Repo.insert(changeset) do
      {:ok, db_fact} ->
        fact = schema_to_map(db_fact)
        new_state = Map.put(state, fact_id, fact)
        Logger.info("[SceneFactStore] Appended fact: #{fact_id}")
        {:reply, {:ok, fact}, new_state}

      {:error, changeset} ->
        Logger.error("[SceneFactStore] Failed to append fact: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset_error_reason(changeset)}, state}
    end
  end

  @impl true
  def handle_call({:list_for_session, tenant_id, session_id}, _from, state) do
    facts =
      state
      |> Map.values()
      |> Enum.filter(&(&1["tenant_id"] == tenant_id and &1["session_id"] == session_id))
      |> Enum.sort_by(& &1["created_at"])

    {:reply, {:ok, facts}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.SceneFact)
    {:reply, :ok, %{}}
  end

  defp convert_to_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> generate_uuid_from_string(value)
    end
  end

  defp convert_to_uuid(value), do: value

  defp generate_uuid_from_string(string) when is_binary(string) do
    hash = :crypto.hash(:sha256, string)
    <<uuid_int::128>> = binary_part(hash, 0, 16)
    <<uuid_int::128>> |> Ecto.UUID.cast() |> elem(1)
  end

  defp schema_to_map(%BotArmyRpg.Schemas.SceneFact{} = fact) do
    %{
      "id" => Ecto.UUID.cast!(fact.id) |> to_string(),
      "tenant_id" => fact.tenant_id |> to_string(),
      "user_id" => if(fact.user_id, do: fact.user_id |> to_string(), else: nil),
      "session_id" => fact.session_id |> to_string(),
      "content" => fact.content,
      "category" => fact.category,
      "source" => fact.source,
      "created_at" => fact.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => fact.updated_at |> NaiveDateTime.to_iso8601()
    }
  end

  defp changeset_error_reason(%Ecto.Changeset{} = changeset) do
    {:validation_error, Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp changeset_error_reason(_), do: :database_error

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
