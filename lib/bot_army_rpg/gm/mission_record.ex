defmodule BotArmyRpg.GM.MissionRecord do
  @moduledoc """
  What a finished mission leaves for the one who went on it to tell.

  `debrief/1` is the record of one mission: its scene, the party as the theme names it, each turn
  (who, what they tried, how it went) and the GM's own lines. It is witness-scoped on purpose. A
  persona's backstory, secret, relationships, carried items and demeanor live in the theme and are
  never read here, so a letter written from this can say only what the party saw, and the stories
  behind the names stay Eir's to tell over time.

  `recent/1` lists the leader's finished missions that played, so a writer can find the ones it has
  not told yet.

  A mission is a session no person owns, led by a bot, that was played to its end. A table a person
  plays at, one still running, and one that played no turn are not missions to tell.
  """

  alias BotArmyRpg.GM.Narrator
  alias BotArmyRpg.Themes.Archetype

  @default_limit 10
  @max_limit 50

  @spec debrief(map()) :: {:ok, map()} | {:error, atom()}
  def debrief(params) do
    tenant_id = tenant_of(params)

    with {:ok, id} <- required(params["session_id"], :session_id_required),
         {:ok, session} <- session_store().get(tenant_id, id),
         :ok <- finished_mission(session) do
      theme = current_theme(tenant_id)
      party = party_of(session, tenant_id, theme)
      names = Map.new(party, &{&1.id, &1["name"]})
      turns = turns_of(session, names)

      {:ok,
       %{
         "session_id" => session["id"],
         "scene" => session["scene_description"],
         "ended_at" => session["ended_at"],
         "party" => Enum.map(party, &Map.take(&1, ["name", "bot_id"])),
         "turns" => turns,
         "story" => story_of(tenant_id, session["id"])
       }}
    end
  end

  @spec recent(map()) :: {:ok, map()} | {:error, atom()}
  def recent(params) do
    tenant_id = tenant_of(params)
    limit = limit_of(params["limit"])

    with {:ok, leader} <- required(params["leader_bot_id"], :leader_bot_id_required),
         {:ok, sessions} when is_list(sessions) <- session_store().list(tenant_id) do
      missions =
        sessions
        |> Enum.filter(&(finished_mission(&1) == :ok and led_by?(&1, leader)))
        |> Enum.filter(&after_since?(&1, params["since"]))
        |> Enum.sort_by(&(&1["ended_at"] || ""), :desc)
        |> Enum.take(limit)
        |> Enum.map(fn s ->
          %{
            "session_id" => s["id"],
            "ended_at" => s["ended_at"],
            "scene" => s["scene_description"],
            "turns" => length(history(s))
          }
        end)

      {:ok, %{"missions" => missions}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unreadable_sessions}
    end
  end

  # -- what a mission is ---------------------------------------------------------------

  defp finished_mission(%{"user_id" => user}) when is_binary(user) and user != "",
    do: {:error, :not_a_mission}

  defp finished_mission(%{"status" => "ended"} = session) do
    if history(session) == [], do: {:error, :nothing_happened}, else: :ok
  end

  defp finished_mission(_session), do: {:error, :still_running}

  defp led_by?(session, leader),
    do: leader in (session |> Map.get("character_ids", %{}) |> Map.values())

  defp after_since?(_session, nil), do: true
  defp after_since?(session, since), do: (session["ended_at"] || "") > since

  defp history(session), do: get_in(session, ["metadata", "turn_state", "turn_history"]) || []

  # -- the parts -----------------------------------------------------------------------

  defp party_of(session, tenant_id, theme) do
    order = get_in(session, ["metadata", "turn_state", "turn_order"]) || []
    ids = Map.get(session, "character_ids", %{})
    ordered = order ++ (Map.keys(ids) -- order)

    for id <- ordered, Map.has_key?(ids, id) do
      bot_id = ids[id]

      name =
        case character_store().get(tenant_id, id) do
          {:ok, %{"name" => stored} = character} when is_binary(stored) ->
            Archetype.display_name(theme, character)

          _ ->
            bot_id
        end

      %{:id => id, "name" => name, "bot_id" => bot_id}
    end
  end

  # The store keeps the newest turn first; a person tells it from the start.
  defp turns_of(session, names) do
    size = max(map_size(Map.get(session, "character_ids", %{})), 1)

    session
    |> history()
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {turn, index} ->
      %{
        "round" => div(index, size) + 1,
        "name" => Map.get(names, turn["character_id"], "someone"),
        "action" => Narrator.verb_of(get_in(turn, ["action", "action_type"])),
        "outcome" => turn["outcome"]
      }
    end)
  end

  defp story_of(tenant_id, session_id) do
    case scene_fact_store().list_for_session(tenant_id, session_id) do
      {:ok, facts} when is_list(facts) ->
        facts
        |> Enum.filter(&(&1["source"] == "gm" and &1["category"] == "narration"))
        |> Enum.sort_by(&(&1["created_at"] || ""))
        |> Enum.map(&String.trim(to_string(&1["content"] || "")))
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  # -- plumbing ------------------------------------------------------------------------

  defp required(value, _error) when is_binary(value) and value != "", do: {:ok, value}
  defp required(_value, error), do: {:error, error}

  defp limit_of(n) when is_integer(n) and n >= 1, do: min(n, @max_limit)
  defp limit_of(_), do: @default_limit

  defp tenant_of(params),
    do: params["tenant_id"] || BotArmyLibraryRuntime.Tenant.default_tenant_id()

  defp current_theme(tenant_id) do
    case theme_store().get_current(tenant_id) do
      {:ok, theme} when is_map(theme) -> theme
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp session_store,
    do: Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)

  defp character_store,
    do: Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)

  defp scene_fact_store,
    do: Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)

  defp theme_store, do: Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
end
