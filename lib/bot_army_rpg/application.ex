defmodule BotArmyRpg.Application do
  @moduledoc "OTP Application for the RPG bot. Manages campaign, character, and scene lifecycle."
  use Application

  @version Mix.Project.config()[:version]

  # Which children to start is a question about the running system, so it is asked at
  # call time and answered by config.
  #
  # It used to be `@env String.to_atom(System.get_env("MIX_ENV") || "prod")` — a
  # COMPILE-time read of an OS environment variable. `mix test` compiles into
  # `_build/test` and then runs whatever text is in there, so a test build compiled while
  # `MIX_ENV` happened to be unset carried `:prod` and started the durable stores, the
  # Repo and the NATS Consumer *inside the test run*. Nothing in the source showed it; it
  # depended on which shell last compiled the tree. The push hook caught it on
  # 2026-09-29 as six `{:already_started, pid}` failures in the party store tests: the
  # application had started the very store the test wanted to supervise.
  defp test_env?, do: Application.get_env(:bot_army_rpg, :env, :prod) == :test

  @impl true
  def start(_type, _args) do
    children = [
      {BotArmyRpg.LoreKeeper, []}
    ]

    children = if test_env?(), do: children, else: children ++ [{BotArmyRpg.Repo, []}]

    children =
      children ++
        if test_env?(),
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
            {BotArmyRpg.CampaignRosterStore, []},
            # The party the context reads. It was never in this list, so every call to
            # `rpg.adventure.context.query` reached a `GenServer.call` on a name with no
            # process behind it, raised, and — because a handler that raises never
            # replies — left the caller waiting instead of answering (measured live
            # 2026-09-29: 12s, no reply).
            {BotArmyRpg.PartyStore, []}
          ]

    children =
      children ++
        if test_env?(),
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
              {BotArmyLibraryLearning.OutcomeTracker,
               [repo: BotArmyRpg.Repo, name: :rpg_outcome_tracker]}
            ] ++ maybe_add_health_responder()

    opts = [strategy: :one_for_one, name: BotArmyRpg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_health_responder do
    if Application.get_env(:bot_army_library_runtime, :pack_mode, false),
      do: [],
      else: [
        {BotArmyLibraryRuntime.Health.Responder,
         [bot_name: :rpg, repo: BotArmyRpg.Repo, version: @version]}
      ]
  end
end
