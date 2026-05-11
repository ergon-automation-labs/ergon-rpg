defmodule BotArmyRpg.Repo.Migrations.CreateRpgThemes do
  use Ecto.Migration

  def change do
    create table(:rpg_themes, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:setting, :string, null: false)
      add(:tone, :string, null: false)
      add(:mechanic, :string, null: false)
      add(:vocabulary, :map, default: %{})
      add(:templates, :map, default: %{})
      add(:npc_personas, :map, default: %{})
      add(:is_current, :boolean, default: false)
      add(:changed_by, :string)
      add(:tenant_id, :uuid, null: false)

      timestamps()
    end

    create(index(:rpg_themes, [:tenant_id]))
    create(index(:rpg_themes, [:is_current]))
  end
end
