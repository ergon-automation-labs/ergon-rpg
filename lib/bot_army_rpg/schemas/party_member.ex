defmodule BotArmyRpg.Schemas.PartyMember do
  @moduledoc """
  One companion, in one identity's party.

  The row is the membership, not a copy of the character. Name, class and race are kept
  because a party must still be able to name a member whose character cannot be read —
  dropping her would report a party of four as a party of three, which is a reading
  nobody took. Level and stats are deliberately *not* here: they change, and the
  character store is their one live answer.

  `character_id` says `Ecto.UUID` because the column is a uuid. A `:string` field over a
  uuid column is the shape that once let a non-uuid actor id past a changeset and into
  Postgres, where it raised *inside a store's `handle_call`* (0.15.44, `rpg_xp_events`);
  here the cast refuses it before a query is built. There is deliberately no foreign key
  to `rpg_characters`: a well-formed id that names no character is accepted, so a
  companion can outlive the character row she points at.

  `role` is what a member is *in this party*, not a copy of anything the character store
  knows: a `companion`, or the one `narrator` a party may have. It is a designation the
  window can render and a rule the store enforces (see
  `BotArmyRpg.PartyStore.set_narrator/3`); it is deliberately not a voice, and nothing
  here claims a bot said anything.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  # The two things a member can be in a party. `narrator` is held by at most one member —
  # the store's write is what keeps it singular — so the list is a vocabulary, and
  # "exactly one" is a rule the changeset cannot state about a set of rows.
  @roles ["companion", "narrator"]

  schema "rpg_party_members" do
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)
    field(:character_id, Ecto.UUID)
    field(:bot_id, :string)
    field(:name, :string)
    field(:class, :string)
    field(:race, :string)
    field(:role, :string, default: "companion")
    field(:joined_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [
      :tenant_id,
      :user_id,
      :character_id,
      :bot_id,
      :name,
      :class,
      :race,
      :role,
      :joined_at
    ])
    |> validate_required([:tenant_id, :user_id, :character_id, :joined_at])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:tenant_id, :user_id, :character_id])
  end
end
