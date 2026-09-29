defmodule BotArmyRpg.Test.PostgresHelper do
  @moduledoc """
  Resets a *test* database's schema, so an integration test starts from the migrations.

  The guard is the point. `reset_schema!/1` drops a schema, and the only thing standing
  between a mistyped `BOT_ARMY_RPG_DB_NAME` and a dropped production schema is the name
  the repo is actually connected to — so this refuses to run against anything that is
  not named `*_test`, rather than trusting the environment it was called from.
  """

  @doc """
  Drops and recreates `public`, so `Release.migrate/0` can build the schema from scratch.

  Raises rather than returning an error: a test whose setup did not do what it said must
  not run on yesterday's schema.
  """
  def reset_schema!(repo) do
    database = repo.config()[:database]

    if is_nil(database) or not String.ends_with?(database, "_test") do
      raise ArgumentError, """
      Refusing to drop the schema of #{inspect(database)}: that is not a test database.
      Point BOT_ARMY_RPG_DB_NAME at a database whose name ends in `_test`.
      """
    end

    repo.query!("DROP SCHEMA public CASCADE")
    repo.query!("CREATE SCHEMA public")
    repo.query!("GRANT ALL ON SCHEMA public TO public")
    :ok
  end
end
