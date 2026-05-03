defmodule BotArmyRpg.Schemas.SceneFactTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.SceneFact

  test "changeset with valid attrs" do
    changeset =
      SceneFact.changeset(%SceneFact{}, %{
        "session_id" => Ecto.UUID.generate(),
        "content" => "The door creaks open",
        "tenant_id" => Ecto.UUID.generate()
      })

    assert changeset.valid?
  end

  test "changeset requires session_id" do
    changeset =
      SceneFact.changeset(%SceneFact{}, %{
        "content" => "Something happens",
        "tenant_id" => Ecto.UUID.generate()
      })

    assert Keyword.has_key?(changeset.errors, :session_id)
  end

  test "changeset requires content" do
    changeset =
      SceneFact.changeset(%SceneFact{}, %{
        "session_id" => Ecto.UUID.generate(),
        "tenant_id" => Ecto.UUID.generate()
      })

    assert Keyword.has_key?(changeset.errors, :content)
  end

  test "changeset defaults category to observation" do
    changeset =
      SceneFact.changeset(%SceneFact{}, %{
        "session_id" => Ecto.UUID.generate(),
        "content" => "A shadow moves",
        "tenant_id" => Ecto.UUID.generate()
      })

    # Schema default ensures category is "observation" even without casting
    assert changeset.data.category == "observation"
  end
end
