defmodule BotArmyRpg.IdentityBotClient do
  @moduledoc """
  Best-effort integration with bot_army_identity.

  This is intentionally non-blocking: RPG identity binding remains available even if
  the identity bot is unavailable or still evolving its request/reply contracts.
  """

  require Logger

  @identity_timeout_ms 2000

  def sync_from_bind(tenant_id, normalized_user_id, payload) when is_map(payload) do
    identity_user_id = Map.get(payload, "identity_user_id")
    identity_email = Map.get(payload, "identity_email")
    identity_display_name = Map.get(payload, "identity_display_name")

    cond do
      is_binary(identity_user_id) and identity_user_id != "" ->
        request_identity_get(tenant_id, normalized_user_id, identity_user_id)

      is_binary(identity_email) and identity_email != "" ->
        request_identity_create(
          tenant_id,
          normalized_user_id,
          identity_email,
          identity_display_name
        )

      true ->
        :skipped
    end
  end

  defp request_identity_get(tenant_id, requester_user_id, identity_user_id) do
    message = %{
      "event" => "users.user.get",
      "tenant_id" => tenant_id,
      "user_id" => requester_user_id,
      "payload" => %{"user_id" => identity_user_id}
    }

    case publisher().request("users.user.get", message,
           timeout_ms: @identity_timeout_ms,
           circuit_breaker_key: "rpg:users.user.get"
         ) do
      {:ok, response} ->
        {:ok, "users.user.get", response}

      {:error, reason} ->
        Logger.warning("[IdentityBotClient] users.user.get failed: #{inspect(reason)}")
        {:error, "users.user.get", reason}
    end
  end

  defp request_identity_create(tenant_id, requester_user_id, email, display_name) do
    payload =
      %{"email" => email}
      |> maybe_put("display_name", display_name)

    message = %{
      "event" => "users.user.create",
      "tenant_id" => tenant_id,
      "user_id" => requester_user_id,
      "payload" => payload
    }

    case publisher().request("users.user.create", message,
           timeout_ms: @identity_timeout_ms,
           circuit_breaker_key: "rpg:users.user.create"
         ) do
      {:ok, response} ->
        {:ok, "users.user.create", response}

      {:error, reason} ->
        Logger.warning("[IdentityBotClient] users.user.create failed: #{inspect(reason)}")
        {:error, "users.user.create", reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end
end
