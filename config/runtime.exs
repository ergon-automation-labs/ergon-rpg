import Config

config :bot_army_library_runtime, :auto_start_services, true

nats_host = System.get_env("NATS_HOST", "localhost")

nats_port =
  if config_env() == :test do
    4223
  else
    String.to_integer(System.get_env("NATS_PORT", "4223"))
  end

config :bot_army_library_runtime, :nats,
  servers: [{nats_host, nats_port}],
  ping_interval: 5000,
  max_reconnect_attempts: 3,
  reconnect_delay_ms: 100

config :bot_army_rpg, BotArmyRpg.Repo,
  database:
    System.get_env("BOT_ARMY_RPG_DB_NAME") || System.get_env("DATABASE_NAME") || "ergon_rpg",
  hostname:
    System.get_env("BOT_ARMY_RPG_DB_HOST") || System.get_env("DATABASE_HOST") || "localhost",
  port:
    String.to_integer(
      System.get_env("BOT_ARMY_RPG_DB_PORT") || System.get_env("DATABASE_PORT") || "30003"
    ),
  username:
    System.get_env("BOT_ARMY_RPG_DB_USER") || System.get_env("DATABASE_USER") || "postgres",
  password:
    System.get_env("BOT_ARMY_RPG_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD") ||
      "postgres",
  pool_size: 3,
  ssl: false

config :bot_army_library_learning, ecto_repos: [BotArmyLearning.Repo]

config :bot_army_library_learning, BotArmyLearning.Repo,
  database:
    System.get_env("BOT_ARMY_RPG_DB_NAME") || System.get_env("DATABASE_NAME") || "ergon_rpg",
  hostname:
    System.get_env("BOT_ARMY_RPG_DB_HOST") || System.get_env("DATABASE_HOST") || "localhost",
  port:
    String.to_integer(
      System.get_env("BOT_ARMY_RPG_DB_PORT") || System.get_env("DATABASE_PORT") || "30003"
    ),
  username:
    System.get_env("BOT_ARMY_RPG_DB_USER") || System.get_env("DATABASE_USER") || "postgres",
  password:
    System.get_env("BOT_ARMY_RPG_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD") ||
      "postgres",
  pool_size: 5,
  ssl: false

config :bot_army_rpg,
  stale_campaign_closer_enabled:
    System.get_env("STALE_CAMPAIGN_CLOSER_ENABLED", "true") in ["1", "true", "yes"],
  stale_campaign_stale_days: String.to_integer(System.get_env("STALE_CAMPAIGN_STALE_DAYS", "30")),
  stale_campaign_check_interval_ms:
    String.to_integer(System.get_env("STALE_CAMPAIGN_CHECK_INTERVAL_MS", "3600000"))
