defmodule BotArmyRpg.Repo.Migrations.AddRulesToRpgThemes do
  use Ecto.Migration

  def change do
    alter table(:rpg_themes) do
      add(:rules, :map, default: %{})
    end
  end
end
