defmodule BotArmyRpg.Handlers.IdentityHandler do
  @moduledoc "Handles NATS messages for binding/unbinding user identities to characters."
  require Logger

  def handle_bind(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    case BotArmyRpg.Identity.bind_user(message, tenant_id) do
      {:ok, normalized_user_id} ->
        identity_sync =
          case BotArmyRpg.IdentityBotClient.sync_from_bind(tenant_id, normalized_user_id, params) do
            :skipped ->
              %{"status" => "skipped", "reason" => "no_identity_bot_fields"}

            {:ok, subject, _response} ->
              %{"status" => "ok", "subject" => subject}

            {:error, subject, reason} ->
              %{"status" => "error", "subject" => subject, "reason" => inspect(reason)}
          end

        :ok = BotArmyRpg.Identity.record_identity_sync(message, tenant_id, identity_sync)

        response = %{
          "tenant_id" => tenant_id,
          "user_id" => normalized_user_id,
          "bound" => true,
          "identity_sync" => identity_sync
        }

        {:ok, response}

      {:error, reason} ->
        Logger.warning("[IdentityHandler] Bind failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_resolve(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    binding = BotArmyRpg.Identity.resolve_binding(message, tenant_id)

    case binding do
      %{"user_id" => user_id} = resolved ->
        {:ok,
         %{
           "tenant_id" => tenant_id,
           "bound" => true,
           "user_id" => user_id,
           "identity_sync" => Map.get(resolved, "identity_sync")
         }}

      _ ->
        {:ok,
         %{
           "tenant_id" => tenant_id,
           "bound" => false,
           "user_id" => nil,
           "identity_sync" => nil
         }}
    end
  end
end
