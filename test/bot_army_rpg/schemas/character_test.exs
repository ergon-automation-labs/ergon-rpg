defmodule BotArmyRpg.Schemas.CharacterTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.Character

  test "changeset with valid attrs" do
    changeset =
      Character.changeset(%Character{}, %{
        "name" => "Aria",
        "tenant_id" => Ecto.UUID.generate()
      })

    assert changeset.valid?
  end

  test "changeset requires name" do
    changeset = Character.changeset(%Character{}, %{"tenant_id" => Ecto.UUID.generate()})
    assert Keyword.has_key?(changeset.errors, :name)
  end

  test "changeset requires tenant_id" do
    changeset = Character.changeset(%Character{}, %{"name" => "Aria"})
    assert Keyword.has_key?(changeset.errors, :tenant_id)
  end

  test "changeset accepts jsonb stats" do
    stats = %{"ability_scores" => %{"str" => 18, "dex" => 14}}

    changeset =
      Character.changeset(%Character{}, %{
        "name" => "Aria",
        "tenant_id" => Ecto.UUID.generate(),
        "stats" => stats
      })

    assert changeset.valid?
    assert get_in(changeset.changes, [:stats]) == stats
  end
end
