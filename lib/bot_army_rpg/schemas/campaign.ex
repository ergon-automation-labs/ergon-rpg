defmodule BotArmyRpg.Schemas.Campaign do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "rpg_campaigns" do
    field(:tenant_id, Ecto.UUID)
    field(:gtd_project_id, Ecto.UUID)
    field(:theme_snapshot, :map)
    field(:status, :string, default: "active")
    field(:started_at, :utc_datetime_usec)
    field(:ended_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [:tenant_id, :gtd_project_id, :theme_snapshot, :status, :started_at, :ended_at])
    |> validate_required([:tenant_id, :gtd_project_id, :theme_snapshot, :started_at])
    |> validate_inclusion(:status, ["active", "completed", "archived"])
  end
end
