defmodule BotArmyRpg.Repo.Migrations.CreateRpgPartyMembers do
  use Ecto.Migration

  def change do
    create table(:rpg_party_members, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid, null: false)
      add(:character_id, :uuid, null: false)
      add(:bot_id, :string)
      add(:name, :string)
      add(:class, :string)
      add(:race, :string)
      add(:role, :string, null: false, default: "companion")
      add(:joined_at, :utc_datetime_usec, null: false)

      timestamps()
    end

    # One companion is in one identity's party once. The index is the rule, not the
    # store's read-then-write: two callers racing on the same recruit both pass a read
    # and only the database can refuse the second insert.
    create(unique_index(:rpg_party_members, [:tenant_id, :user_id, :character_id]))
    create(index(:rpg_party_members, [:tenant_id, :user_id]))
    create(index(:rpg_party_members, [:character_id]))
    create(index(:rpg_party_members, [:bot_id]))
  end
end
