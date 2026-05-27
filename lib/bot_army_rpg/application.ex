defmodule BotArmyRpg.Application do
  @moduledoc "OTP Application for the RPG bot. Manages campaign, character, and scene lifecycle."
  use Application

  @version Mix.Project.config()[:version]
  @env String.to_atom(System.get_env("MIX_ENV") || "prod")

  @impl true
  def start(_type, _args) do
    children = [
      {BotArmyRpg.LoreKeeper, []}
    ]

    children = if @env == :test, do: children, else: children ++ [{BotArmyRpg.Repo, []}]

    children =
      children ++
        if @env == :test,
          do: [],
          else: [
            {BotArmyRpg.IdentityBindingStore, []},
            {BotArmyRpg.CharacterStore, []},
            {BotArmyRpg.QuestStore, []},
            {BotArmyRpg.SessionStore, []},
            {BotArmyRpg.SceneFactStore, []},
            {BotArmyRpg.ThemeStore, []},
            {BotArmyRpg.CampaignStore, []},
            {BotArmyRpg.XpEventStore, []},
            {BotArmyRpg.CampaignRosterStore, []}
          ]

    children =
      children ++
        if @env == :test,
          do: [],
          else:
            [
              {BotArmyRpg.NATS.Consumer, []},
              {BotArmyRpg.LoreSubscriber, []},
              {BotArmyRpg.ProgressionSubscriber, []},
              {BotArmyRpg.ProjectSubscriber, []},
              {BotArmyRpg.StaleCampaignCloser, []},
              {BotArmyRpg.PulsePublisher, []},
              {BotArmyRpg.DailyNarrator, []},
              {BotArmyRpg.ConsequenceEngine, []},
              {BotArmyLearning.OutcomeTracker,
               [repo: BotArmyRpg.Repo, name: :rpg_outcome_tracker]}
            ] ++ maybe_add_health_responder()

    opts = [strategy: :one_for_one, name: BotArmyRpg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_health_responder do
    if Application.get_env(:bot_army_library_runtime, :pack_mode, false),
      do: [],
      else: [
        {BotArmyRuntime.Health.Responder,
         [bot_name: :rpg, repo: BotArmyRpg.Repo, version: @version]}
      ]
  end
end
