defmodule BotArmyRpg.PartyRead do
  @moduledoc """
  The one read that answers "what party is this identity in?", and the one place its
  refusals are mapped.

  A party is keyed by `{tenant_id, user_id}`. A character with no user — the live
  `gtd_bot` character carries `user_id: nil` (2026-09-29) — has no party for the read to
  report, and `nil` is not a key the store answers for: asking it anyway raised, and the
  raise took the Consumer process down with it and left the caller with silence. The read
  reports no party; it does not manufacture one out of a question the store was never
  able to answer.

  Two handlers ask this now — the window's context and a turn's narration — so the
  policy lives here rather than in either of them: one idea of what a party is and one
  mapping of its refusals (N+56).

  ## The key

  A party is keyed by the UUID a user id normalizes to, and the routes normalize before
  they key it (`Identity.resolve_user_id/2`) — so this read normalizes too, or a caller
  holding the name an operator uses for herself ("abby", the identity the dashboard
  recruits a party under) would ask the store for a row it cannot cast and be told the
  party is invalid rather than read. One rule, one owner: `Identity.normalize_user_id/1`.
  """

  alias BotArmyRpg.{Identity, PartyStore}

  @doc """
  The party for this identity, or the reason it could not be read.

  `{:ok, map}` is an answer, and `%{}` is a party with no members: this identity has no
  user to key one by, or the store holds no party for it. `{:error, reason}` is a
  refusal, and the caller decides what a refusal means for the thing it is doing.
  """
  def read(_tenant_id, nil), do: {:ok, %{}}

  def read(tenant_id, user_id) when is_binary(tenant_id) and is_binary(user_id) do
    case store().get_party(tenant_id, Identity.normalize_user_id(user_id)) do
      {:ok, party} -> {:ok, party}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  def read(_tenant_id, _user_id), do: {:ok, %{}}

  @doc """
  The member of this identity's party who narrates, or `nil`.

  `{:ok, member}` is who narrates, `{:ok, nil}` is a party that names no narrator (or no
  party at all), and `{:error, reason}` is the read's refusal, carried as it came. Who
  narrates is `PartyStore.narrator/1`'s answer and never this module's: this only asks the
  party for it.

  Two callers owe this question the same answer — a resolved turn (`GMHandler`) and a line
  in the window's chat (`PartyChat`) — so it is one function rather than two spellings of
  it.
  """
  def narrator(tenant_id, user_id) do
    with {:ok, party} <- read(tenant_id, user_id) do
      {:ok, PartyStore.narrator(party)}
    end
  end

  @doc """
  A refusal reduced to its kind.

  A dead `GenServer.call` carries its arguments in the reason, and for this read those
  arguments are the party's key. A log line records the shape, never the key (N+64).
  """
  def shape(reason) when is_tuple(reason), do: elem(reason, 0)
  def shape(reason), do: reason

  defp store, do: Application.get_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStore)
end
