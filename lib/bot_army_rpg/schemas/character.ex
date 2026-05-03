defmodule BotArmyRpg.Schemas.Character do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "rpg_characters" do
    field(:name, :string)
    field(:race, :string)
    field(:class, :string)
    field(:level, :integer, default: 1)
    field(:stats, :map)
    field(:inventory, :map)
    field(:notes, :string)
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [
      :name,
      :race,
      :class,
      :level,
      :stats,
      :inventory,
      :notes,
      :tenant_id,
      :user_id
    ])
    |> validate_required([:name, :tenant_id])
  end
end
