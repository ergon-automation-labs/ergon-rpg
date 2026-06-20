defmodule RpgBot.Release do
  @moduledoc """
  Release tasks for the RPG bot.

  Migrations are run via the shared BotArmyRuntime.Ecto.MigrationRunner:

      /path/to/rpg_bot/bin/rpg_bot eval 'RpgBot.Release.migrate()'

  Called from Salt during bot deployment, before the bot starts.
  """

  @app :bot_army_rpg

  def migrate do
    BotArmyRuntime.Ecto.MigrationRunner.run(
      repo_module: BotArmyRpg.Repo,
      app_module: @app
    )
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end
end
