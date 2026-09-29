defmodule BotArmyRpg.Schemas.XpEventTest do
  @moduledoc """
  The XP event's own rules, with no database, no store and no mock.

  A changeset is a pure value - it can be built and inspected without a Repo - so this is
  the layer that actually decides whether an XP event is well-formed, and the layer where
  the uuid shape is enforced. The handler above it only checks that a value is a *string*.

  It matters because of what a wrong `actor_id` used to do: the column is a uuid but the
  field was declared `:string`, so a non-uuid passed this changeset, reached Postgres, and
  raised invalid-input-syntax *inside the store's `handle_call`*. The store died and the
  caller got an exit instead of a refusal. The refusal belongs here, and now it is here.
  """

  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.XpEvent

  @campaign "00000000-0000-0000-0000-0000000000c1"
  @actor "00000000-0000-0000-0000-0000000000a1"
  @tenant "00000000-0000-0000-0000-000000000001"

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "rpg_campaign_id" => @campaign,
        "actor_kind" => "player",
        "actor_id" => @actor,
        "delta" => 10,
        "reason_code" => "quest",
        "tenant_id" => @tenant
      },
      overrides
    )
  end

  defp error_fields(changeset) do
    changeset.errors |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  test "a complete event is valid" do
    assert XpEvent.changeset(%XpEvent{}, attrs()).valid?
  end

  test "a campaign id that is not a uuid is refused by the cast, not by Postgres" do
    changeset = XpEvent.changeset(%XpEvent{}, attrs(%{"rpg_campaign_id" => "not-a-uuid"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:rpg_campaign_id]
  end

  test "an actor id that is not a uuid is refused here, before any store is called" do
    changeset = XpEvent.changeset(%XpEvent{}, attrs(%{"actor_id" => "gtd_bot"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:actor_id]
  end

  test "a missing field is reported as missing, not as invalid" do
    changeset = XpEvent.changeset(%XpEvent{}, Map.delete(attrs(), "delta"))

    refute changeset.valid?
    assert error_fields(changeset) == [:delta]
    assert {"can't be blank", _} = changeset.errors[:delta]
  end

  test "an actor kind outside player/npc is refused, and the error names the field" do
    changeset = XpEvent.changeset(%XpEvent{}, attrs(%{"actor_kind" => "goblin"}))

    refute changeset.valid?
    assert error_fields(changeset) == [:actor_kind]
    assert {"is invalid", details} = changeset.errors[:actor_kind]
    assert details[:validation] == :inclusion
  end

  test "a negative delta is accepted: a correction is not junk" do
    assert XpEvent.changeset(%XpEvent{}, attrs(%{"delta" => -10})).valid?
  end

  test "an empty actor id is refused" do
    changeset = XpEvent.changeset(%XpEvent{}, attrs(%{"actor_id" => ""}))

    refute changeset.valid?
    assert error_fields(changeset) == [:actor_id]
  end
end
