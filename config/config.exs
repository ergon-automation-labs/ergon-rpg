import Config

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
  database: "ergon_rpg",
  hostname: "localhost",
  port: 30003,
  username: "postgres",
  password: "postgres",
  pool_size: 10

config :bot_army_library_learning, ecto_repos: [BotArmyLearning.Repo]

config :bot_army_library_learning, BotArmyLearning.Repo,
  database: "ergon_rpg",
  hostname: "localhost",
  port: 30003,
  username: "postgres",
  password: "postgres",
  pool_size: 5

# Logger metadata keys for domain-specific context
config :logger, :default_formatter, metadata: [:timestamp, :level, :module, :function, :error]

if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
