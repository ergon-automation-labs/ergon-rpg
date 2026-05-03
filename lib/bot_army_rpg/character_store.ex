defmodule BotArmyRpg.CharacterStore do
  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def create(payload) when is_map(payload), do: GenServer.call(@server, {:create, payload})
  def get(tenant_id, character_id), do: GenServer.call(@server, {:get, tenant_id, character_id})

  def update(tenant_id, character_id, payload),
    do: GenServer.call(@server, {:update, tenant_id, character_id, payload})

  def list(tenant_id), do: GenServer.call(@server, {:list, tenant_id})
  def clear, do: GenServer.call(@server, :clear)

  @impl true
  def init(_opts) do
    Logger.info("[CharacterStore] Starting")

    state =
      try do
        characters = BotArmyRpg.Repo.all(BotArmyRpg.Schemas.Character)

        Enum.reduce(characters, %{}, fn char, acc ->
          Map.put(acc, char.id |> to_string(), schema_to_map(char))
        end)
      rescue
        _ ->
          Logger.warning("[CharacterStore] Database unavailable, starting empty")
          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    character_id = Ecto.UUID.generate()
    tenant_id = payload["tenant_id"] || BotArmyRuntime.Tenant.default_tenant_id()
    user_id = Map.get(payload, "user_id")

    stats = Map.get(payload, "stats") || BotArmyRpg.Defaults.default_pathfinder_stats()
    inventory = Map.get(payload, "inventory") || BotArmyRpg.Defaults.default_inventory()

    changeset =
      BotArmyRpg.Schemas.Character.changeset(
        %BotArmyRpg.Schemas.Character{id: character_id},
        %{
          "tenant_id" => convert_to_uuid(tenant_id),
          "user_id" => if(user_id, do: convert_to_uuid(user_id), else: nil),
          "name" => payload["name"],
          "race" => Map.get(payload, "race"),
          "class" => Map.get(payload, "class"),
          "level" => Map.get(payload, "level", 1),
          "stats" => stats,
          "inventory" => inventory,
          "notes" => Map.get(payload, "notes")
        }
      )

    case BotArmyRpg.Repo.insert(changeset) do
      {:ok, db_char} ->
        character = schema_to_map(db_char)
        new_state = Map.put(state, character_id, character)
        Logger.info("[CharacterStore] Created character: #{character_id}")
        {:reply, {:ok, character}, new_state}

      {:error, changeset} ->
        Logger.error("[CharacterStore] Failed to create character: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset_error_reason(changeset)}, state}
    end
  end

  @impl true
  def handle_call({:get, tenant_id, character_id}, _from, state) do
    case Map.get(state, character_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      character ->
        if character["tenant_id"] == tenant_id do
          {:reply, {:ok, character}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:update, tenant_id, character_id, payload}, _from, state) do
    case Map.get(state, character_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      character ->
        if character["tenant_id"] != tenant_id do
          {:reply, {:error, :not_found}, state}
        else
          character_uuid = Ecto.UUID.cast!(character_id)

          case BotArmyRpg.Repo.transaction(fn ->
                 db_char = BotArmyRpg.Repo.get(BotArmyRpg.Schemas.Character, character_uuid)

                 if db_char do
                   changeset =
                     BotArmyRpg.Schemas.Character.changeset(db_char, %{
                       "name" => Map.get(payload, "name", db_char.name),
                       "race" => Map.get(payload, "race", db_char.race),
                       "class" => Map.get(payload, "class", db_char.class),
                       "level" => Map.get(payload, "level", db_char.level),
                       "stats" => Map.get(payload, "stats", db_char.stats),
                       "inventory" => Map.get(payload, "inventory", db_char.inventory),
                       "notes" => Map.get(payload, "notes", db_char.notes)
                     })

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
              new_state = Map.put(state, character_id, updated)
              Logger.info("[CharacterStore] Updated character: #{character_id}")
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
    characters =
      state
      |> Map.values()
      |> Enum.filter(&(&1["tenant_id"] == tenant_id))

    {:reply, {:ok, characters}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.Character)
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

  defp schema_to_map(%BotArmyRpg.Schemas.Character{} = char) do
    %{
      "id" => Ecto.UUID.cast!(char.id) |> to_string(),
      "tenant_id" => char.tenant_id |> to_string(),
      "user_id" => if(char.user_id, do: char.user_id |> to_string(), else: nil),
      "name" => char.name,
      "race" => char.race,
      "class" => char.class,
      "level" => char.level,
      "stats" => char.stats,
      "inventory" => char.inventory,
      "notes" => char.notes,
      "created_at" => char.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => char.updated_at |> NaiveDateTime.to_iso8601()
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
