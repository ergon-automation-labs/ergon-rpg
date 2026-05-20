defmodule BotArmyRpg.SessionStore do
  @moduledoc "In-memory + Ecto store for active RPG session state."
  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def create(payload) when is_map(payload), do: GenServer.call(@server, {:create, payload})
  def get(tenant_id, session_id), do: GenServer.call(@server, {:get, tenant_id, session_id})

  def update(tenant_id, session_id, payload),
    do: GenServer.call(@server, {:update, tenant_id, session_id, payload})

  def list(tenant_id), do: GenServer.call(@server, {:list, tenant_id})
  def clear, do: GenServer.call(@server, :clear)

  @impl true
  def init(_opts) do
    Logger.info("[SessionStore] Starting")

    state =
      try do
        sessions = BotArmyRpg.Repo.all(BotArmyRpg.Schemas.Session)

        Enum.reduce(sessions, %{}, fn session, acc ->
          Map.put(acc, session.id |> to_string(), schema_to_map(session))
        end)
      rescue
        _ ->
          Logger.warning("[SessionStore] Database unavailable, starting empty")
          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    session_id = Ecto.UUID.generate()
    tenant_id = payload["tenant_id"] || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(payload, "user_id")

    changeset =
      BotArmyRpg.Schemas.Session.changeset(
        %BotArmyRpg.Schemas.Session{id: session_id},
        %{
          "tenant_id" => convert_to_uuid(tenant_id),
          "user_id" => if(user_id, do: convert_to_uuid(user_id), else: nil),
          "status" => Map.get(payload, "status", "active"),
          "scene_description" => Map.get(payload, "scene_description"),
          "character_ids" => Map.get(payload, "character_ids", %{}),
          "metadata" => Map.get(payload, "metadata", %{})
        }
      )

    case BotArmyRpg.Repo.insert(changeset) do
      {:ok, db_session} ->
        session = schema_to_map(db_session)
        new_state = Map.put(state, session_id, session)
        Logger.info("[SessionStore] Created session: #{session_id}")
        {:reply, {:ok, session}, new_state}

      {:error, changeset} ->
        Logger.error("[SessionStore] Failed to create session: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset_error_reason(changeset)}, state}
    end
  end

  @impl true
  def handle_call({:get, tenant_id, session_id}, _from, state) do
    case Map.get(state, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        if session["tenant_id"] == tenant_id do
          {:reply, {:ok, session}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:update, tenant_id, session_id, payload}, _from, state) do
    case Map.get(state, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        if session["tenant_id"] != tenant_id do
          {:reply, {:error, :not_found}, state}
        else
          session_uuid = Ecto.UUID.cast!(session_id)

          case BotArmyRpg.Repo.transaction(fn ->
                 db_session = BotArmyRpg.Repo.get(BotArmyRpg.Schemas.Session, session_uuid)

                 if db_session do
                   update_fields = %{
                     "status" => Map.get(payload, "status", db_session.status),
                     "scene_description" =>
                       Map.get(payload, "scene_description", db_session.scene_description),
                     "character_ids" =>
                       Map.get(payload, "character_ids", db_session.character_ids),
                     "metadata" => Map.get(payload, "metadata", db_session.metadata)
                   }

                   update_fields =
                     case Map.get(payload, "status") do
                       "paused" ->
                         Map.put(
                           update_fields,
                           "paused_at",
                           NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
                         )

                       "ended" ->
                         Map.put(
                           update_fields,
                           "ended_at",
                           NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
                         )

                       _ ->
                         update_fields
                     end

                   changeset = BotArmyRpg.Schemas.Session.changeset(db_session, update_fields)

                   case BotArmyRpg.Repo.update(changeset) do
                     {:ok, updated} -> updated
                     {:error, cs} -> BotArmyRpg.Repo.rollback(cs)
                   end
                 else
                   BotArmyRpg.Repo.rollback(:not_found)
                 end
               end) do
            {:ok, updated_db} ->
              updated = schema_to_map(updated_db)
              new_state = Map.put(state, session_id, updated)
              Logger.info("[SessionStore] Updated session: #{session_id}")
              {:reply, {:ok, updated}, new_state}

            {:error, :not_found} ->
              {:reply, {:error, :not_found}, state}

            {:error, changeset} ->
              {:reply, {:error, changeset_error_reason(changeset)}, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:list, tenant_id}, _from, state) do
    sessions =
      state
      |> Map.values()
      |> Enum.filter(&(&1["tenant_id"] == tenant_id))

    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.Session)
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

  defp schema_to_map(%BotArmyRpg.Schemas.Session{} = session) do
    %{
      "id" => Ecto.UUID.cast!(session.id) |> to_string(),
      "tenant_id" => session.tenant_id |> to_string(),
      "user_id" => if(session.user_id, do: session.user_id |> to_string(), else: nil),
      "status" => session.status,
      "scene_description" => session.scene_description,
      "character_ids" => session.character_ids,
      "metadata" => session.metadata,
      "paused_at" =>
        if(session.paused_at, do: session.paused_at |> NaiveDateTime.to_iso8601(), else: nil),
      "ended_at" =>
        if(session.ended_at, do: session.ended_at |> NaiveDateTime.to_iso8601(), else: nil),
      "created_at" => session.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => session.updated_at |> NaiveDateTime.to_iso8601()
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
