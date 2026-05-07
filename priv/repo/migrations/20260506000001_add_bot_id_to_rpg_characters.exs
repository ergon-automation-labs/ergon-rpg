defmodule BotArmyRpg.Repo.Migrations.AddBotIdToRpgCharacters do
  use Ecto.Migration

  def change do
    alter table(:rpg_characters) do
      add(:bot_id, :string)
    end

    create(index(:rpg_characters, [:bot_id]))
  end
end
