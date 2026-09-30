defmodule BotArmyRpg.Handlers.SessionContextHandler do
  @moduledoc """
  Handles `rpg.session.gather_context` — narrative context for other bots.

  Fetches the active RPG session, scene facts, character, current theme, and the
  party the window's identity walks with, so fitness.chat, synapse, or any other
  bot can flavor responses with Resistance Chronicle narrative state.
  """

  require Logger

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp scene_fact_store do
    Application.get_env(:bot_army_rpg, :scene_fact_store, BotArmyRpg.SceneFactStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  defp theme_store do
    Application.get_env(:bot_army_rpg, :theme_store, BotArmyRpg.ThemeStore)
  end

  defp party_store do
    Application.get_env(:bot_army_rpg, :party_store, BotArmyRpg.PartyStore)
  end

  @doc """
  Gather narrative context for a user/bot interaction.

  Expected payload:
    - "user_id" (string, required)
    - "bot_id" (string, optional — character of the speaking bot)
    - "session_id" (string, optional — if known)
    - "tenant_id" (string, optional)
    - "fact_limit" (integer, optional — max scene facts, default 10)

  Returns `{:ok, context_map}` or `{:error, reason}`.

  The context always carries `"party"`: the roster this identity walks with, `%{}`
  when the store answered that it has none, and `nil` when the roster could not be
  read at all. Those last two are different facts (`nil` is not an empty party), and
  an unreadable roster never takes the window down.
  """
  def handle_gather_context(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = params["user_id"] || BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    bot_id = params["bot_id"]
    session_id = params["session_id"]
    fact_limit = Map.get(params, "fact_limit", 10)

    with {:ok, session} <- find_active_session(tenant_id, user_id, session_id),
         {:ok, facts} <- fetch_scene_facts(tenant_id, session["id"], fact_limit),
         {:ok, character} <- fetch_character(tenant_id, user_id, bot_id),
         {:ok, theme} <- fetch_theme(tenant_id) do
      context =
        %{
          "session_id" => session["id"],
          "session_status" => session["status"],
          "scene_description" => session["scene_description"],
          "session_metadata" => session["metadata"] || %{},
          "character" => character,
          "theme" => theme,
          "scene_facts" => Enum.map(facts, & &1["content"]),
          "tenant_id" => tenant_id,
          "user_id" => user_id
        }
        |> maybe_party(tenant_id, user_id)
        |> maybe_carry_history(tenant_id, user_id, session["id"], params)

      {:ok, context}
    end
  end

  # --- Private ---

  # Who the window's identity walks with. The party rides in the context rather than
  # being something a caller has to ask for: the bots that flavor a reply out of this
  # read are exactly the ones that never knew to ask, and since 0.15.46 the roster is
  # durable (`rpg_party_members`), so carrying it is a reading and not a guess.
  #
  # It is read through `fetch_party/2` — the same function the bot-centric adventure
  # context uses — so there is one idea of what a party is and one mapping of its
  # refusals.
  #
  # Three answers, and they are not interchangeable: a party (whose `members` may be
  # empty), `%{}` when the store answered that this identity has none, and `nil` when
  # the party could not be read at all. `nil` is not an empty party, and an unreadable
  # roster must not take the window down: the window is the read, and the party is
  # something it carries — the same rule as the carry below.
  defp maybe_party(context, tenant_id, user_id) do
    case fetch_party(tenant_id, user_id) do
      {:ok, party} -> Map.put(context, "party", party)
      {:error, reason} -> unreported_party(context, inspect(shape(reason)))
    end
  rescue
    e ->
      # The kind of failure, not its message: a `FunctionClauseError`'s message carries
      # the arguments it was called with, and those are the party's key. The store logs
      # the detail itself ([PartyStore] Could not …).
      unreported_party(context, "raised #{inspect(e.__struct__)}")
  catch
    :exit, reason -> unreported_party(context, "exited #{inspect(shape(reason))}")
  end

  # The story so far: the newest turns of this identity's *other* windows, so a window
  # opens with what came before it instead of cold. Asked for explicitly, and a consumer
  # that does not ask gets no key at all — a field this bot never sent is not a reading
  # (N+26). A carry that cannot be read is reported as `nil` (unreported) and never as
  # `[]` (nothing came before), because those are different facts and the second one
  # would be invented. The carry never takes the window down: the window is the read.
  #
  # The carry takes *turns*, and `story_only: true` is where that is asked for: a note
  # the machinery wrote is not something that happened in her story, and carrying one
  # would put a test's words into her scene (`SceneFactStore.story?/1` says which facts
  # are notes). The exclusion happens inside the store, before the limit, so the carry
  # still answers the newest `carry_limit` turns.
  defp maybe_carry_history(context, tenant_id, user_id, session_id, params) do
    if Map.get(params, "carry_history", false) do
      Map.put(context, "carry_history", carry_history(tenant_id, user_id, session_id, params))
    else
      context
    end
  end

  defp carry_history(tenant_id, user_id, session_id, params) do
    opts = [
      exclude_session_id: session_id,
      user_id: user_id,
      limit: Map.get(params, "carry_limit", 10),
      story_only: true
    ]

    case scene_fact_store().list_recent_for_tenant(tenant_id, opts) do
      {:ok, facts} ->
        facts
        |> Enum.reverse()
        |> Enum.map(&carry_row/1)

      {:error, reason} ->
        Logger.warning("[SessionContext] Carry history unread: #{inspect(reason)}")
        nil
    end
  end

  # Four fields, and no fifth: the line, who said it, which window it is from, and when.
  defp carry_row(fact) do
    %{
      "content" => fact["content"],
      "source" => fact["source"],
      "session_id" => fact["session_id"],
      "at" => fact["created_at"]
    }
  end

  # The window, when the caller did not name one: the one this identity touched most
  # recently. Which window that is is a domain decision with several readers, so it
  # lives in `BotArmyRpg.Sessions` rather than being re-derived here (it used to be
  # derived here *and* in `find_active_session_for_user/2`, both taking the store's
  # first — that is, arbitrary — open window).
  defp find_active_session(tenant_id, user_id, nil) do
    case BotArmyRpg.Sessions.active_for(tenant_id, user_id) do
      {:ok, session} -> {:ok, session}
      {:error, :bad_store_answer} -> refuse_bad_store_answer()
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_active_session(tenant_id, _user_id, session_id) do
    case session_store().get(tenant_id, session_id) do
      {:ok, session} ->
        if session["status"] == "active" do
          {:ok, session}
        else
          {:error, :session_not_active}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refuse_bad_store_answer do
    Logger.error("[SessionContextHandler] Session store answered something unreadable; refusing")
    {:error, :bad_store_answer}
  end

  defp fetch_scene_facts(tenant_id, session_id, limit) do
    case scene_fact_store().list_for_session(tenant_id, session_id) do
      {:ok, facts} ->
        recent =
          facts
          |> Enum.sort_by(& &1["created_at"], :desc)
          |> Enum.take(limit)

        {:ok, recent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_character(tenant_id, _user_id, nil) do
    # No bot_id provided — return minimal context
    Logger.debug(
      "[SessionContext] No bot_id provided for tenant #{tenant_id}, skipping character fetch"
    )

    {:ok, %{}}
  end

  defp fetch_character(tenant_id, _user_id, bot_id) do
    case character_store().get_by_bot_id(tenant_id, bot_id) do
      {:ok, char} -> {:ok, char}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_theme(tenant_id) do
    case theme_store().get_current(tenant_id) do
      {:ok, theme} -> {:ok, theme}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Adventure Context Query (bot-centric)
  # ───────────────────────────────────────────────────────────────────────────

  @doc """
  Query adventure context for a specific bot.

  Expected payload:
    - "bot_id" (string, required)
    - "tenant_id" (string, optional)

  Returns the bot's character, active session, scene facts, party, and theme.
  """
  def handle_adventure_context(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    bot_id = params["bot_id"]

    if is_nil(bot_id) do
      {:error, :missing_bot_id}
    else
      with {:ok, character} <- fetch_character_for_bot(tenant_id, bot_id),
           user_id = character["user_id"],
           {:ok, session} <- find_active_session_for_user(tenant_id, user_id),
           {:ok, facts} <- fetch_scene_facts(tenant_id, session["id"], 10),
           {:ok, theme} <- fetch_theme(tenant_id),
           {:ok, party} <- fetch_party(tenant_id, user_id) do
        context = %{
          "bot_id" => bot_id,
          "tenant_id" => tenant_id,
          "character" => character,
          "session" => %{
            "id" => session["id"],
            "status" => session["status"],
            "scene_description" => session["scene_description"],
            "metadata" => session["metadata"] || %{}
          },
          "scene_facts" => Enum.map(facts, & &1["content"]),
          "theme" => theme,
          "party" => party
        }

        {:ok, context}
      end
    end
  end

  defp fetch_character_for_bot(tenant_id, bot_id) do
    case character_store().get_by_bot_id(tenant_id, bot_id) do
      {:ok, char} -> {:ok, char}
      {:error, :not_found} -> {:error, :no_character}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_active_session_for_user(tenant_id, user_id) do
    case BotArmyRpg.Sessions.active_for(tenant_id, user_id) do
      {:ok, session} -> {:ok, session}
      {:error, :bad_store_answer} -> refuse_bad_store_answer()
      {:error, reason} -> {:error, reason}
    end
  end

  # A party is keyed by {tenant_id, user_id}. A character with no user — the live
  # `gtd_bot` character carries `user_id: nil` (2026-09-29) — has no party for the read
  # to report, and `nil` is not a key the store answers for: asking it anyway raised,
  # which took the Consumer process down with it and left the caller with silence.
  # The read reports no party; it does not manufacture one out of a question the store
  # was never able to answer.
  defp fetch_party(_tenant_id, nil), do: {:ok, %{}}

  defp fetch_party(tenant_id, user_id) do
    case party_store().get_party(tenant_id, user_id) do
      {:ok, party} -> {:ok, party}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  # A dead store's reason is a tuple whose tail is the call that died, and the arguments
  # of that call are the party's key. A log line records the shape, never the key (N+64).
  defp shape(reason) when is_tuple(reason), do: elem(reason, 0)
  defp shape(reason), do: reason

  defp unreported_party(context, what) do
    Logger.warning("[SessionContext] Party unread: #{what}; carrying nil")
    Map.put(context, "party", nil)
  end
end
