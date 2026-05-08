defmodule BotArmyRpg.Repo.Migrations.CreateRpgCharacters do
  use Ecto.Migration

  def change do
    create table(:rpg_characters, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false)
      add(:race, :string)
      add(:class, :string)
      add(:level, :integer, default: 1)
      add(:stats, :map, default: %{})
      add(:inventory, :map, default: %{})
      add(:notes, :text)

      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps()
    end

    create(index(:rpg_characters, [:tenant_id]))
    create(index(:rpg_characters, [:user_id]))
    create(index(:rpg_characters, [:name]))
  end
end
