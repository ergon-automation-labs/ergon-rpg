defmodule BotArmyRpg.Test.FakePartyRepo do
  @moduledoc """
  A party table that lives in ETS, with either half of the database able to fail.

  `BotArmyRpg.PartyRepo` is the only thing in the store that speaks to the party's
  table, and it speaks five plain functions, so a stand-in answers those five and
  nothing else. This
  one is not a fake Ecto: it runs the real changeset (validation is not a database
  feature), it emulates the one rule a database owns, the unique membership, and it
  raises `Ecto.Query.CastError` on a value that is not an id, the way the real repo's
  `where` clauses do — so the store's answer to a *shape* failure is a thing a test can
  drive, and not only the answer to a database that is down.

  The two switches exist because a failed read and a failed write are different events,
  and the store has to answer them differently: a read that fails may never be reported
  as "no party yet", and a write that fails may not leave a member behind. One stand-in
  with a switch can produce each on its own; two stand-ins that each raise everywhere
  could not show the second.

  It cannot prove a query is *valid* — `party_store_db_test.exs` does that against real
  Postgres. It can prove what the store does with the answers, on every `mix test`.
  """

  alias BotArmyRpg.PartyRepo
  alias BotArmyRpg.Schemas.PartyMember

  @table :fake_party_repo
  @broken_reads :fake_party_repo_reads
  @broken_writes :fake_party_repo_writes

  @doc "An empty table, and both halves working."
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    mend()
  end

  @doc "Both halves working again. Leaves the members alone."
  def mend do
    :persistent_term.erase(@broken_reads)
    :persistent_term.erase(@broken_writes)
    :ok
  end

  def break_reads, do: :persistent_term.put(@broken_reads, true)
  def break_writes, do: :persistent_term.put(@broken_writes, true)

  def members(tenant_id, user_id) do
    down_if_broken(@broken_reads, "read the party")
    cast_id!(:user_id, user_id)

    rows()
    |> Enum.filter(&(&1.tenant_id == tenant_id and &1.user_id == user_id))
    |> oldest_first()
    |> Enum.map(&PartyRepo.to_member/1)
  end

  def all_for_tenant(tenant_id) do
    down_if_broken(@broken_reads, "list the tenant's parties")

    rows()
    |> Enum.filter(&(&1.tenant_id == tenant_id))
    |> oldest_first()
    |> Enum.map(&Map.put(PartyRepo.to_member(&1), "user_id", &1.user_id))
  end

  def insert(attrs) do
    down_if_broken(@broken_writes, "write a member")

    changeset = PartyMember.changeset(%PartyMember{}, attrs)

    cond do
      not changeset.valid? ->
        {:error, changeset}

      member?(attrs[:tenant_id], attrs[:user_id], attrs[:character_id]) ->
        # What the unique index would have said, in the shape the store looks for.
        {:error,
         Ecto.Changeset.add_error(changeset, :tenant_id, "has already been taken",
           constraint: :unique
         )}

      true ->
        row = changeset |> Ecto.Changeset.apply_changes() |> ensure_id()
        :ets.insert(@table, {row.id, row})
        {:ok, row}
    end
  end

  def delete(tenant_id, user_id, character_id) do
    down_if_broken(@broken_writes, "remove a member")
    cast_id!(:character_id, character_id)

    doomed =
      rows()
      |> Enum.filter(
        &(&1.tenant_id == tenant_id and &1.user_id == user_id and
            &1.character_id == character_id)
      )

    Enum.each(doomed, &:ets.delete(@table, &1.id))
    {:ok, length(doomed)}
  end

  # The rule the store depends on, in one place: a character the party does not have is
  # refused *before* anything moves — a refusal may not leave the party changed — and then
  # every narrator is demoted and the named member promoted. `nil` names nobody.
  def set_narrator(tenant_id, user_id, character_id) do
    down_if_broken(@broken_writes, "name the party's narrator")
    cast_id!(:character_id, character_id)

    if is_binary(character_id) and not member?(tenant_id, user_id, character_id) do
      {:error, :not_a_member}
    else
      {:ok,
       %{
         demoted: demote_narrators(tenant_id, user_id),
         promoted: promote(tenant_id, user_id, character_id)
       }}
    end
  end

  defp demote_narrators(tenant_id, user_id) do
    holding =
      rows()
      |> Enum.filter(&narrator_row?(&1, tenant_id, user_id))
      |> Enum.map(&%{&1 | role: "companion"})

    Enum.each(holding, &:ets.insert(@table, {&1.id, &1}))
    length(holding)
  end

  defp promote(_tenant_id, _user_id, nil), do: 0

  defp promote(tenant_id, user_id, character_id) do
    row = row_for(tenant_id, user_id, character_id)
    :ets.insert(@table, {row.id, %{row | role: "narrator"}})
    1
  end

  defp narrator_row?(row, tenant_id, user_id) do
    row.tenant_id == tenant_id and row.user_id == user_id and row.role == "narrator"
  end

  defp row_for(_tenant_id, _user_id, nil), do: nil

  defp row_for(tenant_id, user_id, character_id) do
    Enum.find(rows(), fn row ->
      row.tenant_id == tenant_id and row.user_id == user_id and
        row.character_id == character_id
    end)
  end

  # The real repo compares the caller's values against `uuid` columns, so a value that is
  # not an id raises `Ecto.Query.CastError` before any query runs. The stand-in does the
  # same, which is what makes the store's answer to that failure a thing a test can drive:
  # a value the query could not cast is a shape failure, and it may not be reported as the
  # database being unavailable.
  defp cast_id!(field, value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _} ->
        value

      :error ->
        raise Ecto.Query.CastError,
          value: value,
          type: Ecto.UUID,
          message: "cannot cast #{value} to #{field}"
    end
  end

  defp cast_id!(_field, value), do: value

  defp rows, do: :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  defp oldest_first(rows), do: Enum.sort_by(rows, fn row -> {row.joined_at, row.id} end)

  defp ensure_id(row), do: %{row | id: row.id || Ecto.UUID.generate()}

  defp member?(tenant_id, user_id, character_id) do
    Enum.any?(rows(), fn row ->
      row.tenant_id == tenant_id and row.user_id == user_id and
        row.character_id == character_id
    end)
  end

  defp down_if_broken(flag, what) do
    if :persistent_term.get(flag, false) do
      raise "the party database could not #{what}"
    end

    :ok
  end
end
