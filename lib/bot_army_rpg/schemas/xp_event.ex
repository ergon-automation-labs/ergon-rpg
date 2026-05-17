defmodule BotArmyRpg.Schemas.XpEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "rpg_xp_events" do
    field(:rpg_campaign_id, Ecto.UUID)
    field(:actor_kind, :string)
    field(:actor_id, :string)
    field(:delta, :integer)
    field(:reason_code, :string)
    field(:tenant_id, Ecto.UUID)

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:rpg_campaign_id, :actor_kind, :actor_id, :delta, :reason_code, :tenant_id])
    |> validate_required([
      :rpg_campaign_id,
      :actor_kind,
      :actor_id,
      :delta,
      :reason_code,
      :tenant_id
    ])
    |> validate_inclusion(:actor_kind, ["player", "npc"])
  end
end
