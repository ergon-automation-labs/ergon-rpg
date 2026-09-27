defmodule BotArmyRpg.Handlers.SessionHandler do
  @moduledoc "Handles NATS messages for RPG session create, get, and update."
  require Logger

  alias BotArmyRpg.Sessions

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_start(message) do
    params = message["payload"] || message
    {tenant_id, user_id} = identity_of(message, params)

    case open_window(params, tenant_id, user_id) do
      {:ok, session} ->
        {:ok, session}

      {:error, reason} ->
        Logger.error("[SessionHandler] Start failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Enter the window this identity is in — opening one if there is none.

  `rpg.session.start` **always** begins a new window, and its name says so; that is
  how a pile of open windows grew up behind every adventure. This is the subject for
  the other meaning: *the conversation I am in*. It answers with the window
  `BotArmyRpg.Sessions.active_for/2` picks — the one this identity touched most
  recently — or opens one from these same params when there is none.

  The answer is `{"session" => …, "opened" => boolean}`, nested rather than a field
  inside the session: *whether this call created the window* is a fact about the
  reply, and a session that carried it would be claiming something about the call
  that produced it. `rpg.session.started` is published only when a window was really
  opened — an event has to describe an act that happened.
  """
  def handle_open(message) do
    params = message["payload"] || message
    {tenant_id, user_id} = identity_of(message, params)

    case Sessions.active_for(tenant_id, user_id) do
      {:ok, session} ->
        {:ok, %{"session" => session, "opened" => false}}

      {:error, :no_active_session} ->
        case open_window(params, tenant_id, user_id) do
          {:ok, session} ->
            {:ok, %{"session" => session, "opened" => true}}

          {:error, reason} ->
            Logger.error("[SessionHandler] Open failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Whose window, and in whose house. One reader for the two subjects that open a
  # window, so "who is asking" cannot drift between them.
  defp identity_of(message, params) do
    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    {tenant_id, BotArmyRpg.Identity.resolve_user_id(message, tenant_id)}
  end

  # The act of opening a window, in one place: `rpg.session.start` always does this,
  # and `rpg.session.open` does it only when there is none. The event is published
  # here because this is where the window really came into being — a caller that
  # merely found one must not look like it started something. Each caller names its
  # own failure, so a log line still says which subject was asked.
  defp open_window(params, tenant_id, user_id) do
    payload =
      Map.merge(params, %{
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "status" => "active"
      })

    case session_store().create(payload) do
      {:ok, session} ->
        session = maybe_join_bots(session, params, tenant_id)

        BotArmyRpg.NATS.Publisher.publish("rpg.session.started", session,
          tenant_id: tenant_id,
          user_id: user_id
        )

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_pause(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id) do
      metadata = session["metadata"] || %{}

      turn_state = %{
        "character_ids" => session["character_ids"],
        "scene_description" => session["scene_description"],
        "paused_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      new_metadata = Map.put(metadata, "turn_state", turn_state)

      case session_store().update(tenant_id, session_id, %{
             "status" => "paused",
             "metadata" => new_metadata
           }) do
        {:ok, session} ->
          BotArmyRpg.NATS.Publisher.publish("rpg.session.paused", session, tenant_id: tenant_id)
          {:ok, session}

        {:error, reason} ->
          Logger.error("[SessionHandler] Pause failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def handle_resume(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    with {:ok, session} <- session_store().get(tenant_id, session_id) do
      if session["status"] != "paused" do
        {:error, :session_not_paused}
      else
        metadata = session["metadata"] || %{}
        turn_state = Map.get(metadata, "turn_state", %{})

        restored_metadata = Map.drop(metadata, ["turn_state"])

        updates = %{
          "status" => "active",
          "metadata" => restored_metadata
        }

        updates =
          if turn_state["scene_description"] do
            Map.put(updates, "scene_description", turn_state["scene_description"])
          else
            updates
          end

        case session_store().update(tenant_id, session_id, updates) do
          {:ok, session} ->
            BotArmyRpg.NATS.Publisher.publish("rpg.session.resumed", session,
              tenant_id: tenant_id
            )

            {:ok, session}

          {:error, reason} ->
            Logger.error("[SessionHandler] Resume failed: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  def handle_end(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    case session_store().update(tenant_id, session_id, %{"status" => "ended"}) do
      {:ok, session} ->
        BotArmyRpg.NATS.Publisher.publish("rpg.session.ended", session, tenant_id: tenant_id)
        {:ok, session}

      {:error, reason} ->
        Logger.error("[SessionHandler] End failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_describe(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]
    description = params["description"]

    session_store().update(tenant_id, session_id, %{"scene_description" => description})
  end

  def handle_state(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    session_store().get(tenant_id, session_id)
  end

  @doc """
  Every session this tenant holds, with a count.

  The store answers `{:ok, sessions}` — a two-tuple — so it is matched, never
  assumed to be the list itself. The version of this function that took the
  answer and called `length/1` on it raised `ArgumentError` inside the consumer,
  and a handler that raises **never replies**: `rpg.session.list` was a live
  subject that silently hung every caller (found 2026-09-26, fixed below).

  Anything that is not `{:ok, list}` or `{:error, reason}` is refused as
  `:bad_store_answer` rather than guessed at, so a caller hears that the store
  said something unexpected instead of waiting forever for an answer that the
  handler died before sending. The log names the *shape* of the answer and never
  its contents — a session carries a scene description and a user id.
  """
  def handle_list(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    case session_store().list(tenant_id) do
      {:ok, sessions} when is_list(sessions) ->
        {:ok, %{"sessions" => sessions, "count" => length(sessions)}}

      {:error, reason} ->
        {:error, reason}

      other ->
        Logger.error("[SessionHandler] List answered #{shape(other)}; refusing")
        {:error, :bad_store_answer}
    end
  end

  # What an unexpected answer looks like, said without saying what is in it.
  defp shape(tuple) when is_tuple(tuple), do: "a #{tuple_size(tuple)}-tuple"
  defp shape(%{__struct__: module}), do: "a #{inspect(module)}"
  defp shape(list) when is_list(list), do: "a bare list"
  defp shape(other) when is_map(other), do: "a map"
  defp shape(_other), do: "something unexpected"

  @doc """
  Attach a **character** to an **active** session. Caller must resolve to `user_id`;
  that user must own the character (`character.user_id`). Updates `character_ids`
  on the session: `character_id` (string key) → `user_id` string.
  """
  def handle_join(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    session_id = params["session_id"] |> blank_to_nil()
    character_id = params["character_id"] |> blank_to_nil()

    bot_id = params["bot_id"] |> blank_to_nil()

    cond do
      not is_nil(bot_id) ->
        do_bot_join(tenant_id, session_id, bot_id)

      is_nil(user_id) ->
        {:error, :user_id_required}

      is_nil(session_id) ->
        {:error, :session_id_required}

      is_nil(character_id) ->
        {:error, :character_id_required}

      true ->
        do_join(tenant_id, user_id, session_id, character_id)
    end
  end

  @doc """
  Remove a character from a session. Caller must be the same `user_id` stored
  for that `character_id` in `session.character_ids`.
  """
  def handle_leave(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyLibraryRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)
    session_id = params["session_id"] |> blank_to_nil()
    character_id = params["character_id"] |> blank_to_nil()

    cond do
      is_nil(user_id) ->
        {:error, :user_id_required}

      is_nil(session_id) ->
        {:error, :session_id_required}

      is_nil(character_id) ->
        {:error, :character_id_required}

      true ->
        do_leave(tenant_id, user_id, session_id, character_id)
    end
  end

  defp blank_to_nil(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: nil, else: t
  end

  defp blank_to_nil(_), do: nil

  defp do_join(tenant_id, user_id, session_id, character_id) do
    with {:ok, character} <- character_store().get(tenant_id, character_id),
         :ok <- require_character_owner(character, user_id),
         {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session) do
      current = session["character_ids"] || %{}
      key = character_id

      new_ids =
        current
        |> stringify_keys()
        |> Map.put(key, user_id)

      case session_store().update(tenant_id, session_id, %{"character_ids" => new_ids}) do
        {:ok, updated} ->
          BotArmyRpg.NATS.Publisher.publish(
            "rpg.session.joined",
            %{
              "session_id" => session_id,
              "character_id" => character_id,
              "user_id" => user_id
            },
            tenant_id: tenant_id,
            user_id: user_id
          )

          {:ok, updated}

        {:error, _} = err ->
          err
      end
    end
  end

  defp do_leave(tenant_id, user_id, session_id, character_id) do
    with {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_participant(session, character_id, user_id) do
      current =
        (session["character_ids"] || %{})
        |> stringify_keys()

      key = character_id
      new_ids = Map.delete(current, key)

      case session_store().update(tenant_id, session_id, %{"character_ids" => new_ids}) do
        {:ok, updated} ->
          BotArmyRpg.NATS.Publisher.publish(
            "rpg.session.left",
            %{
              "session_id" => session_id,
              "character_id" => character_id,
              "user_id" => user_id
            },
            tenant_id: tenant_id,
            user_id: user_id
          )

          {:ok, updated}

        {:error, _} = err ->
          err
      end
    end
  end

  defp require_character_owner(character, user_id) do
    if character_owner?(character, user_id), do: :ok, else: {:error, :forbidden}
  end

  defp require_session_active(%{"status" => "active"}), do: :ok
  defp require_session_active(_), do: {:error, :session_not_active}

  defp require_participant(session, character_id, user_id) do
    current =
      (session["character_ids"] || %{})
      |> stringify_keys()

    key = character_id

    case Map.get(current, key) do
      ^user_id -> :ok
      nil -> {:error, :not_joined}
      _ -> {:error, :forbidden}
    end
  end

  defp character_owner?(%{"user_id" => owner, "bot_id" => _bot_id}, user_id)
       when is_binary(owner) and is_binary(user_id) do
    owner == user_id
  end

  defp character_owner?(%{"bot_id" => bot_id}, _user_id)
       when is_binary(bot_id) and bot_id != "" do
    # Bot-owned characters are valid for any authenticated user
    true
  end

  defp character_owner?(%{"user_id" => owner}, user_id)
       when is_binary(owner) and is_binary(user_id) do
    owner == user_id
  end

  defp character_owner?(_, _), do: false

  defp maybe_join_bots(session, params, tenant_id) do
    bot_ids = params["bot_ids"] || []

    Enum.reduce(bot_ids, session, fn bot_id, acc ->
      case BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id) do
        {:ok, character} ->
          current = acc["character_ids"] || %{}
          new_ids = Map.put(current, character["id"], bot_id)

          case session_store().update(tenant_id, acc["id"], %{"character_ids" => new_ids}) do
            {:ok, updated} -> updated
            {:error, _} -> acc
          end

        {:error, reason} ->
          Logger.warning(
            "[SessionHandler] Could not join bot #{bot_id} to session #{acc["id"]}: #{inspect(reason)}"
          )

          acc
      end
    end)
  end

  defp do_bot_join(tenant_id, session_id, bot_id) do
    with {:ok, character} <-
           BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id),
         {:ok, session} <- session_store().get(tenant_id, session_id),
         :ok <- require_session_active(session) do
      current = session["character_ids"] || %{}
      new_ids = Map.put(current, character["id"], bot_id)

      case session_store().update(tenant_id, session_id, %{"character_ids" => new_ids}) do
        {:ok, updated} ->
          BotArmyRpg.NATS.Publisher.publish(
            "rpg.session.joined",
            %{
              "session_id" => session_id,
              "character_id" => character["id"],
              "bot_id" => bot_id
            },
            tenant_id: tenant_id
          )

          {:ok, updated}

        {:error, _} = err ->
          err
      end
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
