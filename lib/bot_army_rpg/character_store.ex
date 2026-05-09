defmodule BotArmyRpg.CharacterStore do
  use GenServer
  require Logger

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def create(payload) when is_map(payload), do: GenServer.call(@server, {:create, payload})
  def get(tenant_id, character_id), do: GenServer.call(@server, {:get, tenant_id, character_id})

  def get_by_bot_id(tenant_id, bot_id),
    do: GenServer.call(@server, {:get_by_bot_id, tenant_id, bot_id})

  def update(tenant_id, character_id, payload),
    do: GenServer.call(@server, {:update, tenant_id, character_id, payload})

  def list(tenant_id), do: GenServer.call(@server, {:list, tenant_id})
  def clear, do: GenServer.call(@server, :clear)

  def get_by_user_id(tenant_id, user_id),
    do: GenServer.call(@server, {:get_by_user_id, tenant_id, user_id})

  def award_xp(tenant_id, user_id, xp_amount) when is_integer(xp_amount) and xp_amount >= 0,
    do: GenServer.call(@server, {:award_xp, tenant_id, user_id, xp_amount})

  def add_item(tenant_id, user_id, item) when is_map(item),
    do: GenServer.call(@server, {:add_item, tenant_id, user_id, item})

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
    bot_id = Map.get(payload, "bot_id")

    stats = Map.get(payload, "stats") || BotArmyRpg.Defaults.default_pathfinder_stats()
    inventory = Map.get(payload, "inventory") || BotArmyRpg.Defaults.default_inventory()

    changeset =
      BotArmyRpg.Schemas.Character.changeset(
        %BotArmyRpg.Schemas.Character{id: character_id},
        %{
          "tenant_id" => convert_to_uuid(tenant_id),
          "user_id" => if(user_id, do: convert_to_uuid(user_id), else: nil),
          "bot_id" => bot_id,
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

        Logger.info(
          "[CharacterStore] Created character: #{character_id} name=#{character["name"]}"
        )

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
  def handle_call({:get_by_bot_id, tenant_id, bot_id}, _from, state) do
    result =
      state
      |> Map.values()
      |> Enum.find(fn char ->
        char["tenant_id"] == tenant_id and char["bot_id"] == bot_id
      end)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      character -> {:reply, {:ok, character}, state}
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
                       "notes" => Map.get(payload, "notes", db_char.notes),
                       "bot_id" => Map.get(payload, "bot_id", db_char.bot_id)
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
  def handle_call({:get_by_user_id, tenant_id, user_id}, _from, state) do
    user_uuid = convert_to_uuid(user_id)

    result =
      state
      |> Map.values()
      |> Enum.find(fn char ->
        char["tenant_id"] == tenant_id and char["user_id"] == user_uuid |> to_string()
      end)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      character -> {:reply, {:ok, character}, state}
    end
  end

  @impl true
  def handle_call({:award_xp, tenant_id, user_id, xp_amount}, _from, state) do
    case get_by_user_id(tenant_id, user_id) do
      {:ok, character} ->
        character_id = character["id"]
        stats = Map.get(character, "stats", %{})
        current_xp = Map.get(stats, "xp", 0)
        current_level = Map.get(character, "level", 1)
        xp_to_next = Map.get(stats, "xp_to_next", 500)

        new_xp = current_xp + xp_amount

        {new_level, new_xp_total} =
          if new_xp >= xp_to_next do
            next_level = current_level + 1
            xp_reset = new_xp - xp_to_next
            {next_level, xp_reset}
          else
            {current_level, new_xp}
          end

        new_xp_to_next = new_level * 500

        # Boost primary ability on level up
        new_stats =
          if new_level > current_level do
            boost_primary_ability(stats, character["class"], new_level)
          else
            stats
          end

        # Update with new XP/level
        updated_stats =
          new_stats
          |> Map.put("xp", new_xp_total)
          |> Map.put("xp_to_next", new_xp_to_next)

        case update(tenant_id, character_id, %{
               "level" => new_level,
               "stats" => updated_stats
             }) do
          {:ok, updated_char} ->
            Logger.info(
              "[CharacterStore] #{user_id} earned #{xp_amount} XP, now level #{new_level}"
            )

            {:reply, {:ok, updated_char}, state}

          {:error, reason} ->
            Logger.error("[CharacterStore] Failed to award XP: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end

      {:error, _} ->
        {:reply, {:error, :character_not_found}, state}
    end
  end

  @impl true
  def handle_call({:add_item, tenant_id, user_id, item}, _from, state) do
    case get_by_user_id(tenant_id, user_id) do
      {:ok, character} ->
        character_id = character["id"]
        inventory = Map.get(character, "inventory", %{})
        items = Map.get(inventory, "items", [])
        new_items = [item | items]
        new_inventory = Map.put(inventory, "items", new_items)

        case update(tenant_id, character_id, %{"inventory" => new_inventory}) do
          {:ok, updated_char} ->
            Logger.info("[CharacterStore] Added item #{item["name"]} to #{user_id}'s inventory")

            {:reply, {:ok, updated_char}, state}

          {:error, reason} ->
            Logger.error("[CharacterStore] Failed to add item: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end

      {:error, _} ->
        {:reply, {:error, :character_not_found}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.Character)
    {:reply, :ok, %{}}
  end

  defp boost_primary_ability(stats, class, _new_level) do
    ability_scores = Map.get(stats, "ability_scores", %{})

    boosted =
      case class do
        "Wizard" -> Map.update(ability_scores, "int", 10, &(&1 + 1))
        "Scribe" -> Map.update(ability_scores, "int", 10, &(&1 + 1))
        "Oracle" -> Map.update(ability_scores, "wis", 10, &(&1 + 1))
        "Drillmaster" -> Map.update(ability_scores, "str", 10, &(&1 + 1))
        "Sentinel" -> Map.update(ability_scores, "str", 10, &(&1 + 1))
        "Steward" -> Map.update(ability_scores, "str", 10, &(&1 + 1))
        "Fixer" -> Map.update(ability_scores, "cha", 10, &(&1 + 1))
        "Herald" -> Map.update(ability_scores, "cha", 10, &(&1 + 1))
        "Shapeshifter" -> Map.update(ability_scores, "dex", 10, &(&1 + 1))
        "Archivist" -> Map.update(ability_scores, "wis", 10, &(&1 + 1))
        _ -> Map.update(ability_scores, "str", 10, &(&1 + 1))
      end

    Map.put(stats, "ability_scores", boosted)
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
      "bot_id" => char.bot_id,
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
