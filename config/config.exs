import Config

config :bot_army_rpg, :deployment_status, "deployed"

if File.exists?(".env") do
  File.stream!(".env")
  |> Stream.map(&String.trim_trailing/1)
  |> Stream.reject(&String.starts_with?(&1, "#"))
  |> Stream.reject(&(&1 == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(key, value)
      _ -> nil
    end
  end)
end

config :bot_army_rpg, ecto_repos: [BotArmyRpg.Repo]

config :bot_army_rpg, BotArmyRpg.Repo,
  database: System.get_env("BOT_ARMY_RPG_DB_NAME", "rpg_dev"),
  hostname: System.get_env("BOT_ARMY_RPG_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_RPG_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_RPG_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_RPG_DB_PASSWORD", "postgres"),
  pool_size: 10

config :bot_army_library_learning, ecto_repos: [BotArmyLearning.Repo]

config :bot_army_library_learning, BotArmyLearning.Repo,
  database: System.get_env("BOT_ARMY_RPG_DB_NAME", "rpg_dev"),
  hostname: System.get_env("BOT_ARMY_RPG_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_RPG_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_RPG_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_RPG_DB_PASSWORD", "postgres"),
  pool_size: 5

# Logger metadata keys for domain-specific context
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "[$time] [$level] $message\n",
  metadata: [:correlation_id]

# config/{env}.exs (test.exs, dev.exs, etc.) was never imported, so any
# override it defined (most commonly a *_test database name) was dead code —
# every mix invocation used the settings above unmodified, regardless of
# MIX_ENV. Guarded by File.exists? since not every env has its own file here.
env_config = "#{config_env()}.exs"

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end

