defmodule BotArmyRpg.Schemas.XpEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "rpg_xp_events" do
    # The column is a uuid (see the create-table migration) but this field was `:string`, so
    # a non-uuid actor_id passed the changeset and reached Postgres, which raised
    # invalid-input-syntax *inside the store's handle_call* - the caller got an exit and the
    # store died, instead of a refusal. The field now says what the column says.
    field(:rpg_campaign_id, Ecto.UUID)
    field(:actor_kind, :string)
    # Note there is no foreign key on the campaign id: a well-formed id that names no
    # campaign is accepted here, so XP can outlive the campaign it was awarded in. Malformed
    # ids are refused by the cast; *unknown* ids are not.
    field(:actor_id, Ecto.UUID)
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
