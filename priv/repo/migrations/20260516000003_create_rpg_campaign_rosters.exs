defmodule BotArmyRpg.Repo.Migrations.CreateRpgCampaignRosters do
  use Ecto.Migration

  def change do
    create table(:rpg_campaign_rosters, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:rpg_campaign_id, :uuid, null: false)
      add(:npc_slug, :string, null: false)
      add(:display_name, :string, null: false)
      add(:voice_ref, :string)
      add(:metadata, :map, default: %{})

      add(:tenant_id, :uuid, null: false)
      add(:joined_at, :naive_datetime, null: false)
      add(:left_at, :naive_datetime)

      timestamps()
    end

    create(unique_index(:rpg_campaign_rosters, [:rpg_campaign_id, :npc_slug]))
    create(index(:rpg_campaign_rosters, [:rpg_campaign_id]))
    create(index(:rpg_campaign_rosters, [:npc_slug]))
    create(index(:rpg_campaign_rosters, [:tenant_id]))
  end
end
