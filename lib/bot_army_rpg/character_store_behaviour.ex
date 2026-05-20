defmodule BotArmyRpg.CharacterStoreBehaviour do
  @moduledoc "Behaviour contract for character storage implementations."
  @callback create(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback get(tenant_id :: String.t(), character_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback get_by_bot_id(tenant_id :: String.t(), bot_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
  @callback update(tenant_id :: String.t(), character_id :: String.t(), payload :: map()) ::
              {:ok, map()} | {:error, atom()}
  @callback list(tenant_id :: String.t()) :: {:ok, list(map())}
  @callback clear() :: :ok
end
