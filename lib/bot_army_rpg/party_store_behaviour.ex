defmodule BotArmyRpg.PartyStoreBehaviour do
  @moduledoc """
  Behaviour contract for party/roster storage implementations.

  The whole contract, not the half of it a caller happened to use first: `rpg.party.add`
  and `rpg.party.remove` go through `add_member/3` and `remove_member/3`, and a
  behaviour that lists only `get_party/2` and `list_parties/1` cannot describe a store
  a test is allowed to stand in for. The three write callbacks were missing until the
  party routes were actually wired (2026-09-29), which is why a mock of this behaviour
  could be defined and still refuse to be told what an add returns.

  `set_narrator/3` joined the contract at 0.15.48 for the same reason: naming the party's
  narrator is a write a caller can ask the party for, so a stand-in that cannot be told
  what it answers is not a stand-in for this store. Its `character_id` is nullable —
  `nil` is the request that clears the role, and a mock with a binary-only signature
  would make that request unrepresentable.
  """

  @callback get_party(tenant_id :: String.t(), user_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}

  @callback list_parties(tenant_id :: String.t()) :: {:ok, list(map())}

  @callback add_member(tenant_id :: String.t(), user_id :: String.t(), member :: map()) ::
              {:ok, map()} | {:error, atom()}

  @callback remove_member(
              tenant_id :: String.t(),
              user_id :: String.t(),
              character_id :: String.t()
            ) ::
              {:ok, map()} | {:error, atom()}

  # `character_id` is nilable on purpose: `nil` means "clear the role", which is a
  # different request from naming a member.
  @callback set_narrator(
              tenant_id :: String.t(),
              user_id :: String.t(),
              character_id :: String.t() | nil
            ) ::
              {:ok, map()} | {:error, atom()}

  @callback auto_populate(tenant_id :: String.t(), user_id :: String.t()) ::
              {:ok, map()} | {:error, atom()}
end
