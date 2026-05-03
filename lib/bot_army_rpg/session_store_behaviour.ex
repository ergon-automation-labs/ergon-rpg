defmodule BotArmyRpg.SessionStoreBehaviour do
  @callback create(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback get(tenant_id :: String.t(), session_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback update(tenant_id :: String.t(), session_id :: String.t(), payload :: map()) ::
              {:ok, map()} | {:error, atom()}
  @callback list(tenant_id :: String.t()) :: {:ok, list(map())}
  @callback clear() :: :ok
end
