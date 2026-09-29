defmodule BotArmyRpg.XpEventStoreBehaviour do
  @moduledoc """
  Behaviour contract for the XP ledger.

  Both arities of `handle_get_events` are declared because the handler calls each of them:
  the unfiltered read is a different question from the filtered one, and a mock that could
  only answer one of them would hide the other.
  """

  @callback handle_insert(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback handle_get_events(rpg_campaign_id :: String.t()) :: {:ok, list(map())}
  @callback handle_get_events(rpg_campaign_id :: String.t(), filters :: map()) ::
              {:ok, list(map())}
end
