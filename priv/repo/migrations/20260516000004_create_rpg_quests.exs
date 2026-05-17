defmodule BotArmyRpg.Repo.Migrations.CreateRpgQuests do
  use Ecto.Migration

  def change do
    create table(:rpg_quests, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:character_id, :uuid, null: false)
      add(:title, :string, null: false)
      add(:description, :text)
      add(:narrative_framing, :text)
      add(:priority, :string, default: "normal")
      add(:status, :string, default: "active")
      add(:progress, :map, default: %{})
      add(:rewards, :map, default: %{})
      add(:linked_gtd_id, :uuid)
      add(:success_band, :string)
      add(:dice_roll, :map)
      add(:outcome_score, :float)
      add(:source_category, :string)

      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps()
    end

    create(index(:rpg_quests, [:character_id]))
    create(index(:rpg_quests, [:tenant_id]))
    create(index(:rpg_quests, [:user_id]))
    create(index(:rpg_quests, [:linked_gtd_id]))
    create(index(:rpg_quests, [:status]))
    create(index(:rpg_quests, [:source_category]))
  end
end
