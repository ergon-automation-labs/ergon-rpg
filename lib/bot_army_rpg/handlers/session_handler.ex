defmodule BotArmyRpg.Handlers.SessionHandler do
  require Logger

  defp session_store do
    Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
  end

  defp character_store do
    Application.get_env(:bot_army_rpg, :character_store, BotArmyRpg.CharacterStore)
  end

  def handle_start(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    user_id = BotArmyRpg.Identity.resolve_user_id(message, tenant_id)

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
        Logger.error("[SessionHandler] Start failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_pause(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

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
        BotArmyRuntime.Tenant.default_tenant_id()

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
        BotArmyRuntime.Tenant.default_tenant_id()

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
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]
    description = params["description"]

    session_store().update(tenant_id, session_id, %{"scene_description" => description})
  end

  def handle_state(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

    session_id = params["session_id"]

    session_store().get(tenant_id, session_id)
  end

  @doc """
  Attach a **character** to an **active** session. Caller must resolve to `user_id`;
  that user must own the character (`character.user_id`). Updates `character_ids`
  on the session: `character_id` (string key) → `user_id` string.
  """
  def handle_join(message) do
    params = message["payload"] || message

    tenant_id =
      params["tenant_id"] || message["tenant_id"] ||
        BotArmyRuntime.Tenant.default_tenant_id()

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
        BotArmyRuntime.Tenant.default_tenant_id()

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
