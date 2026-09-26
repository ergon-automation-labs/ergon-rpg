defmodule BotArmyRpg.SceneFactStoreBehaviour do
  @moduledoc "Behaviour contract for scene fact storage implementations."
  @callback append(payload :: map()) :: {:ok, map()} | {:error, atom()}
  @callback list_for_session(tenant_id :: String.t(), session_id :: String.t()) ::
              {:ok, list(map())}
  @doc """
  The newest turns across a tenant's *other* windows — the story so far.

  `opts` carries `:exclude_session_id` (the window being read, whose turns are
  already in hand), `:user_id` (the same identity the window was found by, so a
  household member's story does not become another's) and `:limit`.
  """
  @callback list_recent_for_tenant(tenant_id :: String.t(), opts :: keyword()) ::
              {:ok, list(map())} | {:error, atom()}

  @callback clear() :: :ok
end
