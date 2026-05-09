defmodule BotArmyRpg.Handlers.CharacterHandler do
  require Logger

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_create(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)

    payload =
      Map.merge(params, %{
        "tenant_id" => tenant_id,
        "user_id" => user_id
      })

    case character_store().create(payload) do
      {:ok, character} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.character.created", character,
          tenant_id: tenant_id,
          user_id: user_id
        )

        {:ok, character}

      {:error, reason} ->
        Logger.error("[CharacterHandler] Create failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_get(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    character_id = params["character_id"]

    character_store().get(tenant_id, character_id)
  end

  def handle_update(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    character_id = params["character_id"]

    case character_store().update(tenant_id, character_id, params) do
      {:ok, character} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.character.updated", character,
          tenant_id: tenant_id
        )

        {:ok, character}

      {:error, reason} ->
        Logger.error("[CharacterHandler] Update failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id_filter = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)

    with {:ok, characters} <- character_store().list(tenant_id) do
      normalized_user_id = normalize_user_id(user_id_filter)

      filtered =
        case normalized_user_id do
          nil ->
            characters

          user_id ->
            Enum.filter(characters, fn character ->
              Map.get(character, "user_id") == user_id
            end)
        end

      {:ok, filtered}
    end
  end

  def handle_get_by_bot(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    bot_id = Map.get(params, "bot_id", "")

    if bot_id == "" do
      {:error, :bot_id_required}
    else
      character_store().get_by_bot_id(tenant_id, bot_id)
    end
  end

  def handle_ensure(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    bot_id = Map.get(params, "bot_id", "")

    if bot_id == "" do
      {:error, :bot_id_required}
    else
      BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id)
    end
  end

  defp normalize_user_id(nil), do: nil

  defp normalize_user_id(user_id) when is_binary(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        uuid

      :error ->
        hash = :crypto.hash(:sha256, user_id)
        <<uuid_int::128>> = binary_part(hash, 0, 16)
        <<uuid_int::128>> |> Ecto.UUID.cast() |> elem(1)
    end
  end

  defp normalize_user_id(user_id), do: user_id

  def handle_award_xp(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    xp_amount = params["xp_amount"] || 100

    character_store().award_xp(tenant_id, user_id, xp_amount)
  end

  def handle_equip(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    item_id = params["item_id"]
    slot = params["slot"] || "main_hand"

    with {:ok, character} <- character_store().get_by_user_id(tenant_id, user_id),
         character_id <- character["id"],
         inventory <- Map.get(character, "inventory", %{}),
         items <- Map.get(inventory, "items", []),
         {:ok, item} <- find_item_by_id(items, item_id) do
      updated_inventory =
        inventory
        |> Map.put("equipped", %{slot => item_id})

      character_store().update(tenant_id, character_id, %{"inventory" => updated_inventory})
    else
      {:error, reason} ->
        Logger.error("[CharacterHandler] Equip failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_unequip(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    slot = params["slot"] || "main_hand"

    with {:ok, character} <- character_store().get_by_user_id(tenant_id, user_id),
         character_id <- character["id"],
         inventory <- Map.get(character, "inventory", %{}) do
      updated_inventory =
        inventory
        |> Map.update("equipped", %{}, &Map.delete(&1, slot))

      character_store().update(tenant_id, character_id, %{"inventory" => updated_inventory})
    else
      {:error, reason} ->
        Logger.error("[CharacterHandler] Unequip failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_item_by_id(items, item_id) when is_list(items) do
    case Enum.find(items, fn item -> item["id"] == item_id end) do
      nil -> {:error, :item_not_found}
      item -> {:ok, item}
    end
  end
end
