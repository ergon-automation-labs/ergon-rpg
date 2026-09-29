defmodule BotArmyRpg.CharacterStore do
  @moduledoc "In-memory + Ecto store for bot/player character sheets and stats."
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

  def award_xp_to_bot(tenant_id, bot_id, xp_amount)
      when is_binary(bot_id) and is_integer(xp_amount) and xp_amount >= 0,
      do: GenServer.call(@server, {:award_xp_to_bot, tenant_id, bot_id, xp_amount})

  def add_item(tenant_id, user_id, item) when is_map(item),
    do: GenServer.call(@server, {:add_item, tenant_id, user_id, item})

  @doc """
  One award of XP, as a pure function: level and XP-toward-next, before and after.

  The bar is 500 XP for level 2 and `level * 500` after that. A single award earns at most
  ONE level and the remainder carries toward the next bar - so 5_000 XP is one level, not
  five. That is the curve the characters have already been living with; it is named and
  tested here so that changing it is a decision rather than a discovery.
  """
  def apply_xp(current_level, current_xp, xp_to_next, xp_amount)
      when is_integer(current_level) and is_integer(current_xp) and is_integer(xp_to_next) and
             is_integer(xp_amount) do
    new_xp = current_xp + xp_amount

    if new_xp >= xp_to_next do
      {current_level + 1, new_xp - xp_to_next}
    else
      {current_level, new_xp}
    end
  end

  @doc "The bar to the next level, given the level just reached."
  def xp_to_next(level) when is_integer(level), do: level * 500

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
    tenant_id = payload["tenant_id"] || BotArmyLibraryRuntime.Tenant.default_tenant_id()
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
    case find_by_bot_id(state, tenant_id, bot_id) do
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
          case persist_update(character_id, payload) do
            {:ok, updated} ->
              Logger.info("[CharacterStore] Updated character: #{character_id}")
              {:reply, {:ok, updated}, Map.put(state, character_id, updated)}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
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
    case find_by_user_id(state, tenant_id, user_id) do
      nil -> {:reply, {:error, :not_found}, state}
      character -> {:reply, {:ok, character}, state}
    end
  end

  # A handler runs INSIDE the store, so it must never call this module's own client
  # functions: get_by_user_id/2, update/3 and friends are GenServer.call/3 to the process
  # that is currently executing the handler. OTP detects that and exits with :calling_self -
  # which is exactly what this handler did, so every XP award answered a crash and no XP was
  # ever awarded. Read the state and write through the private helpers below instead.
  @impl true
  def handle_call({:award_xp, tenant_id, user_id, xp_amount}, _from, state) do
    case find_by_user_id(state, tenant_id, user_id) do
      nil -> {:reply, {:error, :character_not_found}, state}
      character -> award_to(character, xp_amount, state, "user #{user_id}")
    end
  end

  # This client existed with a guard and no clause behind it, so any caller - and the party's
  # companions are bot-owned characters, so the path is wanted - took the store down with a
  # FunctionClauseError. Bot and user characters now level by one curve through award_to/5.
  @impl true
  def handle_call({:award_xp_to_bot, tenant_id, bot_id, xp_amount}, _from, state) do
    case find_by_bot_id(state, tenant_id, bot_id) do
      nil -> {:reply, {:error, :character_not_found}, state}
      character -> award_to(character, xp_amount, state, "bot #{bot_id}")
    end
  end

  @impl true
  def handle_call({:add_item, tenant_id, user_id, item}, _from, state) do
    case find_by_user_id(state, tenant_id, user_id) do
      nil ->
        {:reply, {:error, :character_not_found}, state}

      character ->
        character_id = character["id"]
        inventory = Map.get(character, "inventory", %{})
        items = Map.get(inventory, "items", [])
        new_inventory = Map.put(inventory, "items", [item | items])

        case persist_update(character_id, %{"inventory" => new_inventory}) do
          {:ok, updated_char} ->
            Logger.info("[CharacterStore] Added item #{item["name"]} to #{user_id}'s inventory")

            # The reply used to carry the new inventory while the state kept the old one, so
            # the store answered with a character it could not read back until a restart.
            {:reply, {:ok, updated_char}, Map.put(state, character_id, updated_char)}

          {:error, reason} ->
            Logger.error("[CharacterStore] Failed to add item: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.Character)
    {:reply, :ok, %{}}
  end

  # Shared by the read handlers and by every write path: one lookup, not two that can drift.
  defp find_by_user_id(state, tenant_id, user_id) do
    wanted = convert_to_uuid(user_id) |> to_string()

    state
    |> Map.values()
    |> Enum.find(&(&1["tenant_id"] == tenant_id and &1["user_id"] == wanted))
  end

  defp find_by_bot_id(state, tenant_id, bot_id) do
    state
    |> Map.values()
    |> Enum.find(&(&1["tenant_id"] == tenant_id and &1["bot_id"] == bot_id))
  end

  # The one place a character row is written. It never raises: a database that is unavailable
  # is a refusal the caller can read, not a dead store. (The write path used to be reachable
  # only through a public client function, which a handler cannot call without killing the
  # store it is running inside.)
  defp persist_update(character_id, payload) do
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
      {:ok, updated_db} -> {:ok, schema_to_map(updated_db)}
      {:error, :not_found} -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_error_reason(changeset)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("[CharacterStore] Character write unavailable: #{inspect(e.__struct__)}")
      {:error, :database_unavailable}
  end

  defp award_to(character, xp_amount, state, who) do
    stats = Map.get(character, "stats", %{})
    current_level = Map.get(character, "level", 1)

    {new_level, new_xp_total} =
      apply_xp(
        current_level,
        Map.get(stats, "xp", 0),
        Map.get(stats, "xp_to_next", 500),
        xp_amount
      )

    # A level-up boosts the primary ability; XP and the next bar move either way.
    level_stats =
      if new_level > current_level do
        boost_primary_ability(stats, character["class"], new_level)
      else
        stats
      end

    updated_stats =
      level_stats
      |> Map.put("xp", new_xp_total)
      |> Map.put("xp_to_next", xp_to_next(new_level))

    character_id = character["id"]

    case persist_update(character_id, %{"level" => new_level, "stats" => updated_stats}) do
      {:ok, updated_char} ->
        Logger.info("[CharacterStore] #{who} earned #{xp_amount} XP, now level #{new_level}")
        {:reply, {:ok, updated_char}, Map.put(state, character_id, updated_char)}

      {:error, reason} ->
        Logger.error("[CharacterStore] Failed to award XP: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
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
