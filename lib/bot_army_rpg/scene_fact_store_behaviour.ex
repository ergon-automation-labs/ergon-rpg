defmodule BotArmyRpg.SceneFactStoreBehaviour do
  @callback append(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback list_for_session(tenant_id :: String.t(), session_id :: String.t()) ::
              {:ok, list(map())}
  @callback clear() :: :ok
end
