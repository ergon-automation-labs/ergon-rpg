defmodule BotArmyRpg.Application do
  use Application

  @version Mix.Project.config()[:version]
  @env String.to_atom(System.get_env("MIX_ENV") || "prod")

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_character_store()
      |> maybe_add_session_store()
      |> maybe_add_scene_fact_store()
      |> maybe_add_consumer()
      |> maybe_add_pulse_publisher()
      |> maybe_add_health_responder()

    opts = [strategy: :one_for_one, name: BotArmyRpg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.Repo, []} | children]
  end

  defp maybe_add_character_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.CharacterStore, []} | children]
  end

  defp maybe_add_session_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.SessionStore, []} | children]
  end

  defp maybe_add_scene_fact_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.SceneFactStore, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.NATS.Consumer, []} | children]
  end

  defp maybe_add_pulse_publisher(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.PulsePublisher, []} | children]
  end

  defp maybe_add_health_responder(children) do
    if @env == :test do
      children
    else
      [
        {BotArmyRpg.HealthResponder, [bot_name: :rpg, repo: BotArmyRpg.Repo, version: @version]}
        | children
      ]
    end
  end
end
