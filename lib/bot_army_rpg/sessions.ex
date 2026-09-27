defmodule BotArmyRpg.Sessions do
  @moduledoc """
  The window an identity is in.

  A session *is* a window, and an identity may have several open at once, because
  `rpg.session.start` always creates a new one. That makes "the window" a decision
  rather than a lookup, and every reader has to make the same one: the context read
  behind the phone window, the bot-centric adventure read, and `rpg.session.open`.
  The decision lives here, once.

  ## Why the newest, and by what

  The store hands back the values of a map, so its order is not a reading at all —
  taking the first open window made *which conversation am I in* arbitrary, and the
  answer changed as the map was resized. The window an identity means is the one it
  touched most recently, so `updated_at` decides, with `created_at` and then the id
  breaking ties so that two windows made in the same second are still chosen by a
  fact rather than by luck.

  `updated_at` moves when the window is described, joined or paused — and when a turn
  is added to it, which is what makes "most recently touched" mean *the conversation
  we were last in* rather than *the last one whose metadata changed*.
  """

  require Logger

  @doc """
  The newest open window for this identity, or `{:error, :no_active_session}`.

  A store answer that is not `{:ok, sessions}` is refused as `:bad_store_answer`
  rather than raising: a handler that raises never replies at all, which reads to the
  caller as a dead bot instead of a bad answer. The shape of the unexpected answer is
  logged by the caller, never what was in it — a session carries a scene description
  and a user id.
  """
  @spec active_for(String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, :no_active_session} | {:error, term()}
  def active_for(tenant_id, user_id) do
    case store().list(tenant_id) do
      {:ok, sessions} when is_list(sessions) ->
        sessions
        |> Enum.filter(&open_for?(&1, user_id))
        |> newest()

      {:error, reason} ->
        {:error, reason}

      other ->
        Logger.error("[Sessions] The store answered #{shape(other)}; refusing")
        {:error, :bad_store_answer}
    end
  end

  # What an unexpected answer is, said without saying what is in it: a session carries
  # a scene description, a user id, and whoever joined it.
  defp shape(tuple) when is_tuple(tuple), do: "a #{tuple_size(tuple)}-tuple"
  defp shape(list) when is_list(list), do: "a bare list"
  defp shape(%{__struct__: module}), do: "a #{inspect(module)}"
  defp shape(_other), do: "something this module does not know"

  defp open_for?(session, user_id) do
    session["user_id"] == user_id and session["status"] == "active"
  end

  defp newest([]), do: {:error, :no_active_session}

  defp newest(open) do
    {:ok, Enum.max_by(open, &{&1["updated_at"] || "", &1["created_at"] || "", &1["id"] || ""})}
  end

  defp store, do: Application.get_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStore)
end
