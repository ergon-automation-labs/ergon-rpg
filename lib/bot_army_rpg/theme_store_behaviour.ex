defmodule BotArmyRpg.ThemeStoreBehaviour do
  @moduledoc """
  Behaviour for theme persistence and retrieval.
  """

  @callback set_current(tenant_id :: String.t(), theme_data :: map(), changed_by :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback get_current(tenant_id :: String.t()) ::
              {:ok, map()} | {:error, :not_found}

  @callback list(tenant_id :: String.t()) ::
              {:ok, list(map())}

  @callback clear() :: :ok
end
