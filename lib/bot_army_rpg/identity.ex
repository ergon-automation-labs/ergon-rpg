defmodule BotArmyRpg.Identity do
  @moduledoc "Resolves user IDs from NATS messages using identity binding rules."
  @identity_keys ~w(surface client_id channel_id guild_id theme_id connection_id)

  def resolve_user_id(message, tenant_id) do
    params = message["payload"] || message
    explicit_user_id = Map.get(params, "user_id") || Map.get(message, "user_id")

    case normalize_user_id(explicit_user_id) do
      nil ->
        context = identity_context(params, message)

        if map_size(context) == 0 do
          nil
        else
          identity_store().resolve(tenant_id, context)
        end

      user_id ->
        user_id
    end
  end

  def bind_user(message, tenant_id) do
    params = message["payload"] || message
    raw_user_id = Map.get(params, "user_id") || Map.get(message, "user_id")
    context = identity_context(params, message)

    cond do
      is_nil(raw_user_id) ->
        {:error, :user_id_required}

      map_size(context) == 0 ->
        {:error, :identity_context_required}

      true ->
        normalized_user_id = normalize_user_id(raw_user_id)
        identity_store().bind(tenant_id, context, normalized_user_id)
    end
  end

  def resolve_binding(message, tenant_id) do
    params = message["payload"] || message
    context = identity_context(params, message)

    if map_size(context) == 0 do
      nil
    else
      identity_store().resolve_binding(tenant_id, context)
    end
  end

  def record_identity_sync(message, tenant_id, identity_sync) when is_map(identity_sync) do
    params = message["payload"] || message
    context = identity_context(params, message)

    if map_size(context) == 0 do
      :ok
    else
      identity_store().set_identity_sync(tenant_id, context, identity_sync)
    end
  end

  defp identity_context(params, message) do
    Enum.reduce(@identity_keys, %{}, fn key, acc ->
      value = Map.get(params, key) || Map.get(message, key)

      if is_nil(value) or value == "" do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp identity_store do
    Application.get_env(:bot_army_rpg, :identity_store, BotArmyRpg.IdentityBindingStore)
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
end
