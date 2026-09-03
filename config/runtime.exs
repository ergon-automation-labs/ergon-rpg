import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# NATS configuration
if config_env() != :test do
  nats_host = BotArmyLibraryRuntime.ConfigLoader.get("NATS_HOST", "localhost")
  nats_port = BotArmyLibraryRuntime.ConfigLoader.get("NATS_PORT", "4222") |> String.to_integer()

  config :bot_army_library_runtime, :nats,
    servers: [{nats_host, nats_port}],
    ping_interval: 5000,
    max_reconnect_attempts: 3,
    reconnect_delay_ms: 100
end

# Database configuration
if config_env() != :test do
  alias BotArmyLibraryRuntime.Ecto.RuntimeDbConfig

  db_config =
    RuntimeDbConfig.resolve("BOT_ARMY_RPG", database: "ergon_rpg", port: 30003)

  config :bot_army_rpg,
    BotArmyRpg.Repo,
    Keyword.put(Keyword.put(db_config, :pool_size, RuntimeDbConfig.pool_size("BOT_ARMY_RPG", 10)), :ssl, false)

  config :bot_army_library_learning,
    BotArmyLearning.Repo,
    Keyword.put(Keyword.put(db_config, :pool_size, RuntimeDbConfig.pool_size("BOT_ARMY_RPG", 10)), :ssl, false)
end

# RPG Bot specific settings
if config_env() != :test do
  config :bot_army_rpg,
    stale_campaign_closer_enabled:
      BotArmyLibraryRuntime.ConfigLoader.get("STALE_CAMPAIGN_CLOSER_ENABLED", "true") in [
        "1",
        "true",
        "yes"
      ],
    stale_campaign_stale_days:
      BotArmyLibraryRuntime.ConfigLoader.get("STALE_CAMPAIGN_STALE_DAYS", "30")
      |> String.to_integer(),
    stale_campaign_check_interval_ms:
      BotArmyLibraryRuntime.ConfigLoader.get("STALE_CAMPAIGN_CHECK_INTERVAL_MS", "3600000")
      |> String.to_integer()
end

config :bot_army_library_runtime, :auto_start_services, true
