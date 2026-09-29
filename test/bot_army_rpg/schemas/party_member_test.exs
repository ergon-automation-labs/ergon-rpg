defmodule BotArmyRpg.Schemas.PartyMemberTest do
  @moduledoc """
  A membership's own rules, with no database, no store and no mock.

  The changeset is where a malformed membership is refused, and where the uuid shape is
  enforced. It matters for the same reason it did on `rpg_xp_events` (0.15.44): the
  columns are uuids, and a field declared `:string` over a uuid column lets a non-uuid
  through the changeset, into Postgres, and raises *inside a store's `handle_call`* —
  which kills the store and leaves the caller with an exit instead of a refusal.
  """

  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.PartyMember

  @tenant "00000000-0000-0000-0000-000000000001"
  @user "00000000-0000-0000-0000-000000000002"
  @character "11111111-1111-1111-1111-111111111111"

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "tenant_id" => @tenant,
        "user_id" => @user,
        "character_id" => @character,
        "bot_id" => "gtd_bot",
        "name" => "The Lorekeeper",
        "class" => "Scheduler",
        "race" => "Construct",
        "joined_at" => DateTime.utc_now()
      },
      overrides
    )
  end

  defp error_fields(changeset) do
    changeset.errors |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  test "a complete membership is valid" do
    assert PartyMember.changeset(%PartyMember{}, attrs()).valid?
  end

  test "the role is a companion by default" do
    changeset = PartyMember.changeset(%PartyMember{}, attrs())
    assert Ecto.Changeset.get_field(changeset, :role) == "companion"
  end

  test "an identity that is not a uuid is refused by the cast, not by Postgres" do
    changeset = PartyMember.changeset(%PartyMember{}, attrs(%{"user_id" => "her"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:user_id]
  end

  test "a character id that is not a uuid is refused here, before any store is called" do
    changeset = PartyMember.changeset(%PartyMember{}, attrs(%{"character_id" => "gtd_bot"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:character_id]
  end

  test "a missing identity is reported as missing, not as invalid" do
    changeset = PartyMember.changeset(%PartyMember{}, Map.delete(attrs(), "tenant_id"))

    refute changeset.valid?
    assert error_fields(changeset) == [:tenant_id]
    assert {"can't be blank", _} = changeset.errors[:tenant_id]
  end

  test "a role that is not a companion is refused, and the error names the field" do
    changeset = PartyMember.changeset(%PartyMember{}, attrs(%{"role" => "rival"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:role]
    assert {"is invalid", details} = changeset.errors[:role]
    assert details[:validation] == :inclusion
  end

  test "the membership is unique per identity and character, and the changeset says so" do
    # The index is what actually refuses a duplicate; declaring the constraint here is
    # what turns the database's error into a changeset error the store can read.
    changeset = PartyMember.changeset(%PartyMember{}, attrs())

    assert [
             %{
               type: :unique,
               constraint: "rpg_party_members_tenant_id_user_id_character_id_index"
             }
           ] = changeset.constraints
  end
end
