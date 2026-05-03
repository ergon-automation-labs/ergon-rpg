defmodule BotArmyRpg.Schemas.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "rpg_sessions" do
    field(:status, :string, default: "active")
    field(:scene_description, :string)
    field(:character_ids, :map)
    field(:metadata, :map)
    field(:paused_at, :naive_datetime)
    field(:ended_at, :naive_datetime)
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :status,
      :scene_description,
      :character_ids,
      :metadata,
      :paused_at,
      :ended_at,
      :tenant_id,
      :user_id
    ])
    |> validate_required([:tenant_id])
    |> validate_inclusion(:status, ["active", "paused", "ended"])
  end
end
