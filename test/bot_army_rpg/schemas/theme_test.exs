defmodule BotArmyRpg.Schemas.ThemeTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyRpg.Schemas.Theme

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{
        setting: "cyberpunk",
        tone: "hopeful",
        mechanic: "bounties",
        tenant_id: Ecto.UUID.generate()
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert changeset.valid?
    end

    test "invalid without setting" do
      attrs = %{tone: "hopeful", mechanic: "bounties", tenant_id: Ecto.UUID.generate()}
      changeset = Theme.changeset(%Theme{}, attrs)
      refute changeset.valid?
    end

    test "invalid without tone" do
      attrs = %{setting: "cyberpunk", mechanic: "bounties", tenant_id: Ecto.UUID.generate()}
      changeset = Theme.changeset(%Theme{}, attrs)
      refute changeset.valid?
    end

    test "invalid without mechanic" do
      attrs = %{setting: "cyberpunk", tone: "hopeful", tenant_id: Ecto.UUID.generate()}
      changeset = Theme.changeset(%Theme{}, attrs)
      refute changeset.valid?
    end

    test "defaults vocabulary to empty map" do
      attrs = %{
        setting: "cyberpunk",
        tone: "hopeful",
        mechanic: "bounties",
        tenant_id: Ecto.UUID.generate()
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :vocabulary) == %{}
    end

    test "defaults is_current to false" do
      attrs = %{
        setting: "cyberpunk",
        tone: "hopeful",
        mechanic: "bounties",
        tenant_id: Ecto.UUID.generate()
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :is_current) == false
    end

    test "accepts vocabulary as map" do
      attrs = %{
        setting: "cyberpunk",
        tone: "hopeful",
        mechanic: "bounties",
        tenant_id: Ecto.UUID.generate(),
        vocabulary: %{"task" => "bounty"}
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :vocabulary) == %{"task" => "bounty"}
    end
  end
end
