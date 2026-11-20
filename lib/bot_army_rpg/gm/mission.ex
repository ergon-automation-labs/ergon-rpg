defmodule BotArmyRpg.GM.Mission do
  @moduledoc """
  A table that plays without a player: the leader (Eir by default), two crew drawn at
  random from the other bots' characters, a scene the GM sets, and a bounded number of
  rounds. The session is owned by no user, so it never becomes anyone's active table.

  A mission ends by running out of rounds, by `stop/1`, or by a turn that cannot be played;
  `rpg.mission.finished` says which. Crew are bot-played characters only - never the
  leader, a retired character (`*_retired`), or a person's.
  """

  require Logger

  alias BotArmyRpg.GM.{Narrator, TurnManager}
  alias BotArmyRpg.Themes.Archetype
  alias BotArmyRpg.Handlers.GMHandler

  @default_leader "companion_bot"
  @default_rounds 5
  @max_rounds 10
  @crew_size 2

  @spec crew([map()], String.t(), non_neg_integer(), ([map()] -> [map()]), map() | nil) ::
          [map()]
  def crew(characters, leader_bot_id, count, shuffle \\ &Enum.shuffle/1, theme \\ nil) do
    characters
    |> Enum.filter(&eligible?(&1, leader_bot_id))
    |> Enum.uniq_by(& &1["bot_id"])
    |> shuffle.()
    |> Enum.uniq_by(&(Archetype.persona_key(theme, &1["bot_id"]) || &1["bot_id"]))
    |> Enum.take(count)
  end

  defp eligible?(%{"bot_id" => bot_id} = character, leader_bot_id)
       when is_binary(bot_id) and bot_id != "" do
    bot_id != leader_bot_id and not String.ends_with?(bot_id, "_retired") and
      is_nil(character["user_id"])
  end

  defp eligible?(_character, _leader), do: false

  def start(params) do
    tenant_id = params["tenant_id"] || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    leader_bot_id = params["leader_bot_id"] || @default_leader
    rounds = rounds_of(params["rounds"])

    with {:ok, leader} <- character_store().get_by_bot_id(tenant_id, leader_bot_id),
         {:ok, everyone} <- character_store().list(tenant_id),
         theme = current_theme(tenant_id),
         [_ | _] = crew <- crew(everyone, leader_bot_id, @crew_size, &Enum.shuffle/1, theme),
         {:ok, scene} <- scene_for(params, tenant_id),
         party = [leader | crew],
         {:ok, session} <- open_table(tenant_id, scene, party),
         {:ok, session} <- seat_the_round(tenant_id, session) do
      roster =
        Enum.map(
          party,
          &%{
            "character_id" => &1["id"],
            "name" => Archetype.display_name(theme, &1),
            "bot_id" => &1["bot_id"]
          }
        )

      BotArmyRpg.NATS.Publisher.publish(
        "rpg.mission.started",
        %{
          "session_id" => session["id"],
          "scene" => scene,
          "party" => roster,
          "rounds" => rounds,
          "leader_bot_id" => leader_bot_id
        },
        tenant_id: tenant_id
      )

      Task.start(fn -> run(tenant_id, session["id"], rounds, leader_bot_id) end)

      {:ok,
       %{"session_id" => session["id"], "scene" => scene, "party" => roster, "rounds" => rounds}}
    else
      [] -> {:error, :no_crew}
      {:error, _} = error -> error
    end
  end

  def stop(params) do
    tenant_id = params["tenant_id"] || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    session_id = params["session_id"]

    with {:ok, _session} <- session_store().get(tenant_id, session_id),
         {:ok, _} <- session_store().update(tenant_id, session_id, %{"status" => "ended"}) do
      {:ok, %{"session_id" => session_id, "stopped" => true}}
    end
  end

  @doc false
  def run(tenant_id, session_id, rounds, leader_bot_id \\ @default_leader) do
    case safely_play(tenant_id, session_id) do
      {:ok, %{"round" => round}} when is_integer(round) and round <= rounds ->
        run(tenant_id, session_id, rounds, leader_bot_id)

      {:ok, _} ->
        finish(tenant_id, session_id, "rounds_played", leader_bot_id)

      {:error, reason} ->
        finish(tenant_id, session_id, "ended: #{inspect(reason)}", leader_bot_id)
    end
  end

  defp safely_play(tenant_id, session_id) do
    GMHandler.play_turn(tenant_id, session_id)
  rescue
    error -> {:error, {:crashed, Exception.message(error)}}
  end

  defp finish(tenant_id, session_id, why, leader_bot_id) do
    case session_store().get(tenant_id, session_id) do
      {:ok, %{"status" => "ended"}} -> :ok
      _ -> session_store().update(tenant_id, session_id, %{"status" => "ended"})
    end

    BotArmyRpg.NATS.Publisher.publish(
      "rpg.mission.finished",
      %{"session_id" => session_id, "why" => why, "leader_bot_id" => leader_bot_id},
      tenant_id: tenant_id
    )

    Logger.info("[Mission] #{session_id} finished: #{why}")

    case Application.get_env(:bot_army_rpg, :mission_finished_notify) do
      pid when is_pid(pid) -> send(pid, {:mission_finished, session_id})
      _ -> :ok
    end
  end

  defp current_theme(tenant_id) do
    case theme_store().get_current(tenant_id) do
      {:ok, theme} when is_map(theme) -> theme
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp rounds_of(n) when is_integer(n) and n >= 1, do: min(n, @max_rounds)
  defp rounds_of(_), do: @default_rounds

  defp scene_for(params, tenant_id) do
    case params["scene"] do
      seed when is_binary(seed) ->
        case String.trim(seed) do
          "" -> ask_the_gm(tenant_id)
          trimmed -> {:ok, trimmed}
        end

      _ ->
        ask_the_gm(tenant_id)
    end
  end

  defp ask_the_gm(tenant_id) do
    with {:ok, theme} <- theme_store().get_current(tenant_id) do
      Narrator.set_scene(theme)
    end
  end

  defp open_table(tenant_id, scene, party) do
    session_store().create(%{
      "tenant_id" => tenant_id,
      "user_id" => nil,
      "status" => "active",
      "scene_description" => scene,
      "character_ids" => Map.new(party, &{&1["id"], &1["bot_id"]})
    })
  end

  defp seat_the_round(tenant_id, session) do
    session_store().update(tenant_id, session["id"], %{
      "metadata" => TurnManager.build_turn_state(session)
    })
  end

  defp session_store,
    do: Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)

  defp character_store,
    do: Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)

  defp theme_store, do: Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
end
