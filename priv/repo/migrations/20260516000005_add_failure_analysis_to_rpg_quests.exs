defmodule BotArmyRpg.Repo.Migrations.AddFailureAnalysisToRpgQuests do
  use Ecto.Migration

  def change do
    alter table(:rpg_quests) do
      add(:failure_analysis, :map)
    end
  end
end
