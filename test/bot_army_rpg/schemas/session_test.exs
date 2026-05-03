defmodule BotArmyRpg.Schemas.SessionTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.Session

  test "changeset with valid attrs" do
    changeset = Session.changeset(%Session{}, %{"tenant_id" => Ecto.UUID.generate()})
    assert changeset.valid?
  end

  test "changeset requires tenant_id" do
    changeset = Session.changeset(%Session{}, %{})
    assert Keyword.has_key?(changeset.errors, :tenant_id)
  end

  test "changeset validates status inclusion" do
    changeset =
      Session.changeset(%Session{}, %{
        "tenant_id" => Ecto.UUID.generate(),
        "status" => "invalid"
      })

    assert Keyword.has_key?(changeset.errors, :status)
  end

  test "changeset accepts valid statuses" do
    for status <- ["active", "paused", "ended"] do
      changeset =
        Session.changeset(%Session{}, %{
          "tenant_id" => Ecto.UUID.generate(),
          "status" => status
        })

      assert changeset.valid?
    end
  end
end
