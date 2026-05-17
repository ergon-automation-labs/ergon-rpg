defmodule BotArmyRpg.Schemas.CampaignRoster do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "rpg_campaign_rosters" do
    field(:rpg_campaign_id, Ecto.UUID)
    field(:npc_slug, :string)
    field(:display_name, :string)
    field(:tenant_id, Ecto.UUID)
    field(:joined_at, :utc_datetime_usec)
    field(:left_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(roster, attrs) do
    roster
    |> cast(attrs, [:rpg_campaign_id, :npc_slug, :display_name, :tenant_id, :joined_at, :left_at])
    |> validate_required([:rpg_campaign_id, :npc_slug, :display_name, :tenant_id, :joined_at])
    |> unique_constraint([:rpg_campaign_id, :npc_slug])
  end
end
