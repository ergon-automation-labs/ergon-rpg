defmodule BotArmyRpg.Repo.Migrations.CreateRpgCampaigns do
  use Ecto.Migration

  def change do
    create table(:rpg_campaigns, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:rpg_campaign_id, :uuid, null: false)
      add(:gtd_project_id, :uuid, null: false)
      add(:status, :string, null: false, default: "active")
      add(:theme_snapshot, :map, null: false)
      add(:campaign_metadata, :map, default: %{})

      add(:tenant_id, :uuid, null: false)
      add(:started_at, :naive_datetime, null: false)
      add(:ended_at, :naive_datetime)

      timestamps()
    end

    create(unique_index(:rpg_campaigns, [:gtd_project_id]))
    create(unique_index(:rpg_campaigns, [:rpg_campaign_id]))
    create(index(:rpg_campaigns, [:status]))
    create(index(:rpg_campaigns, [:tenant_id]))
    create(index(:rpg_campaigns, [:started_at]))
  end
end
