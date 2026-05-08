defmodule BotArmyRpg.Repo.Migrations.CreateRpgSessions do
  use Ecto.Migration

  def change do
    create table(:rpg_sessions, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:status, :string, null: false, default: "active")
      add(:scene_description, :text)
      add(:character_ids, :map, default: %{})
      add(:metadata, :map, default: %{})
      add(:paused_at, :naive_datetime)
      add(:ended_at, :naive_datetime)

      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps()
    end

    create(index(:rpg_sessions, [:status]))
    create(index(:rpg_sessions, [:tenant_id]))
    create(index(:rpg_sessions, [:user_id]))
  end
end
