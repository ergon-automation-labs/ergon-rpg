defmodule BotArmyRpg.Application do
  use Application

  @version Mix.Project.config()[:version]
  @env String.to_atom(System.get_env("MIX_ENV") || "prod")

  @impl true
  def start(_type, _args) do
    children =
      [{BotArmyRpg.LoreKeeper, []}]
      |> maybe_add_repo()
      |> maybe_add_identity_binding_store()
      |> maybe_add_character_store()
      |> maybe_add_session_store()
      |> maybe_add_scene_fact_store()
      |> maybe_add_theme_store()
      |> maybe_add_consumer()
      |> maybe_add_lore_subscriber()
      |> maybe_add_progression_subscriber()
      |> maybe_add_pulse_publisher()
      |> maybe_add_daily_narrator()
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

  defp maybe_add_identity_binding_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.IdentityBindingStore, []} | children]
  end

  defp maybe_add_session_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.SessionStore, []} | children]
  end

  defp maybe_add_scene_fact_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.SceneFactStore, []} | children]
  end

  defp maybe_add_theme_store(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.ThemeStore, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.NATS.Consumer, []} | children]
  end

  defp maybe_add_lore_subscriber(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.LoreSubscriber, []} | children]
  end

  defp maybe_add_progression_subscriber(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.ProgressionSubscriber, []} | children]
  end

  defp maybe_add_pulse_publisher(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.PulsePublisher, []} | children]
  end

  defp maybe_add_daily_narrator(children) do
    if @env == :test, do: children, else: [{BotArmyRpg.DailyNarrator, []} | children]
  end

  defp maybe_add_health_responder(children) do
    if @env == :test do
      children
    else
      [
        {BotArmyRuntime.Health.Responder,
         [bot_name: :rpg, repo: BotArmyRpg.Repo, version: @version]}
        | children
      ]
    end
  end
end
