defmodule BotArmyRpg.HealthResponder do
  @moduledoc """
  Health check responder for the RPG bot.

  Responds to bot.rpg.health NATS requests with service status.
  """

  use GenServer
  require Logger

  @version Mix.Project.config()[:version]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    bot_name = Keyword.get(opts, :bot_name, :rpg)
    repo = Keyword.get(opts, :repo)
    version = Keyword.get(opts, :version, @version)

    state = %{
      bot_name: bot_name,
      repo: repo,
      version: version
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    if msg.topic == "bot.rpg.health" and msg.reply_to do
      health = %{
        status: "healthy",
        bot: state.bot_name,
        version: state.version,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      reply = BotArmyRuntime.NATS.Reply.ok(health)

      if state.conn do
        Gnat.pub(state.conn, msg.reply_to, reply)
      end
    end

    {:noreply, state}
  end
end
