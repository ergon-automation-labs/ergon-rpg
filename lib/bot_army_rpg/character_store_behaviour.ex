defmodule BotArmyRpg.CharacterStoreBehaviour do
  @moduledoc "Behaviour contract for character storage implementations."
  @callback create(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback get(tenant_id :: String.t(), character_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback get_by_bot_id(tenant_id :: String.t(), bot_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback update(tenant_id :: String.t(), character_id :: String.t(), payload :: map()) ::
              {:ok, map()} | {:error, atom()}
  @callback get_by_user_id(tenant_id :: String.t(), user_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback award_xp(tenant_id :: String.t(), user_id :: String.t(), xp_amount :: integer()) ::
              {:ok, map()} | {:error, atom()}
  @callback list(tenant_id :: String.t()) :: {:ok, list(map())}
  @callback clear() :: :ok
end
