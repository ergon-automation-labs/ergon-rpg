defmodule BotArmyRpg.Repo.Migrations.CreateRpgXpEvents do
  use Ecto.Migration

  def change do
    create table(:rpg_xp_events, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:rpg_campaign_id, :uuid, null: false)
      add(:actor_kind, :string, null: false)
      add(:actor_id, :uuid, null: false)
      add(:delta, :integer, null: false)
      add(:reason_code, :string, null: false)
      add(:gtd_task_id, :uuid)
      add(:correlation_id, :uuid)
      add(:metadata, :map, default: %{})

      add(:tenant_id, :uuid, null: false)

      timestamps()
    end

    create(index(:rpg_xp_events, [:rpg_campaign_id]))
    create(index(:rpg_xp_events, [:actor_kind, :actor_id]))
    create(index(:rpg_xp_events, [:tenant_id]))
    create(index(:rpg_xp_events, [:reason_code]))
    create(index(:rpg_xp_events, [:inserted_at]))
  end
end
