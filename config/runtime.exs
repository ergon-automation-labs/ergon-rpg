import Config

# The salt-rendered config file has to be put somewhere before it can be read: the launchd
# wrapper deliberately skips sourcing an Elixir `%{}` file (it is not shell), and
# `ConfigLoader.get/2` reads `:config_data` from this app's env and then `System.get_env/1` —
# so without these two lines every pillar knob in this file is inert and the release quietly
# runs on its compiled defaults. Measured across the fleet 2026-10-24 (gtd 33c845f5): on
# wife_care the file named the 27B for the press and the running VM answered `nil`, so the
# press silently used the 4B. A bot that reads `ConfigLoader` without loading it reads
# nothing. Guarded off `:test` because a test run has no rendered file and no business
# reading the node's credentials.
if config_env() != :test do
  config_data = BotArmyLibraryRuntime.ConfigLoader.load_config()
  Application.put_env(:bot_army_library_runtime, :config_data, config_data)
end

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# NATS configuration
if config_env() != :test do
  nats_host = BotArmyLibraryRuntime.ConfigLoader.get("NATS_HOST", "localhost")
  nats_port = BotArmyLibraryRuntime.ConfigLoader.get("NATS_PORT", "4223") |> String.to_integer()

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
