defmodule BotArmyRpg.CampaignStoreBehaviour do
  @moduledoc """
  Behaviour contract for campaign storage implementations.

  Declared so a test can stand in for the store. The handler resolves the module at call
  time, and Mox can only mock a function that a behaviour declares — which is why these
  callbacks had to exist before the campaign happy paths could be tested at all.
  """

  @callback handle_insert(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback handle_get_by_project(gtd_project_id :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback handle_get_by_id(rpg_campaign_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback handle_update(rpg_campaign_id :: String.t(), attrs :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback handle_list_active() :: {:ok, list(map())}
end
