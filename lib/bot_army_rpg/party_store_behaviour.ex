defmodule BotArmyRpg.PartyStoreBehaviour do
  @moduledoc "Behaviour contract for party/roster storage implementations."
  @callback get_party(tenant_id :: String.t(), user_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback list_parties(tenant_id :: String.t()) :: {:ok, list(map())}
end
