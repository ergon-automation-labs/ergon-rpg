import Config

config :bot_army_rpg, :character_store, BotArmyRpg.CharacterStoreMock
config :bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock
config :bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStoreMock
config :bot_army_rpg, :theme_store, BotArmyRpg.ThemeStoreMock

config :bot_army_rpg, BotArmyRpg.Repo,
  database: System.get_env("BOT_ARMY_RPG_DB_NAME", "bot_army_rpg_test"),
  hostname: System.get_env("BOT_ARMY_RPG_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_RPG_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_RPG_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_RPG_DB_PASSWORD", "postgres"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

test_nats_port = System.get_env("NATS_PORT", "4223") |> String.to_integer()

config :bot_army_runtime, :nats,
  servers: [{"localhost", test_nats_port}],
  ping_interval: 5000,
  max_reconnect_attempts: 3,
  reconnect_delay_ms: 100
