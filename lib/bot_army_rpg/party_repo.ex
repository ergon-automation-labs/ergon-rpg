defmodule BotArmyRpg.PartyRepo do
  @moduledoc """
  The one place that knows the party's table.

  Everything that reads or writes `rpg_party_members` comes through here, so the table's
  name, its columns and the shape of a membership are spelled once. It is also the seam
  the store is tested through: these five functions are the whole vocabulary, so a test
  can answer them with a stand-in and decide the party's rules on every `mix test`
  instead of only where Postgres happens to be reachable.

  A row becomes the member map the wire already speaks here, once, so the shape is not
  spelled a second time in the store or the handler.
  """
  import Ecto.Query

  alias BotArmyRpg.Repo
  alias BotArmyRpg.Schemas.PartyMember

  @doc "The party's members, oldest first. `[]` means this identity has no party."
  def members(tenant_id, user_id) do
    PartyMember
    |> for_party(tenant_id, user_id)
    |> order_by([m], asc: m.joined_at, asc: m.id)
    |> Repo.all()
    |> Enum.map(&to_member/1)
  end

  @doc "Every membership in a tenant, for listing the tenant's parties."
  def all_for_tenant(tenant_id) do
    PartyMember
    |> where([m], m.tenant_id == ^tenant_id)
    |> order_by([m], asc: m.joined_at, asc: m.id)
    |> Repo.all()
    |> Enum.map(&Map.put(to_member(&1), "user_id", &1.user_id))
  end

  @doc "Recruit a companion. The unique index is what refuses a duplicate."
  def insert(attrs) do
    Repo.insert(PartyMember.changeset(%PartyMember{}, attrs))
  end

  @doc "Take a companion out, by character id. Returns how many rows left."
  def delete(tenant_id, user_id, character_id) do
    {count, _} =
      PartyMember
      |> for_party(tenant_id, user_id)
      |> where([m], m.character_id == ^character_id)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  A membership as the member map the party answers with.

  `joined_at` is rendered as the UTC stamp the wire has always carried, so a row and an
  in-memory member are the same thing to a caller.
  """
  def to_member(%PartyMember{} = row) do
    %{
      "character_id" => row.character_id,
      "bot_id" => row.bot_id,
      "name" => row.name,
      "class" => row.class,
      "race" => row.race,
      "role" => row.role || "companion",
      "joined_at" => utc_stamp(row.joined_at)
    }
  end

  defp for_party(query, tenant_id, user_id) do
    where(query, [m], m.tenant_id == ^tenant_id and m.user_id == ^user_id)
  end

  defp utc_stamp(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp utc_stamp(_absent), do: nil
end
