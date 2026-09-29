defmodule BotArmyRpg.CampaignRosterStoreBehaviour do
  @moduledoc "Behaviour contract for the campaign roster (the NPCs a campaign remembers)."

  @callback handle_get_roster(rpg_campaign_id :: String.t()) :: {:ok, list(map())}
  @callback handle_upsert(
              rpg_campaign_id :: String.t(),
              npc_slug :: String.t(),
              attrs :: map()
            ) :: {:ok, map()} | {:error, term()}
end
