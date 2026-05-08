defmodule BotArmyRpg.Repo.Migrations.CreateRpgSceneFacts do
  use Ecto.Migration

  def change do
    create table(:rpg_scene_facts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:session_id, :uuid, null: false)
      add(:content, :text, null: false)
      add(:category, :string, default: "observation")
      add(:source, :string, default: "gm")

      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps()
    end

    create(index(:rpg_scene_facts, [:session_id]))
    create(index(:rpg_scene_facts, [:category]))
    create(index(:rpg_scene_facts, [:tenant_id]))
  end
end
