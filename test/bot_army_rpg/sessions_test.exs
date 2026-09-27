defmodule BotArmyRpg.SessionsTest do
  @moduledoc """
  Which window an identity is in.

  The store hands back a map's values, so its order is not a reading. Every test here
  pins that the choice is made from the data — `updated_at`, then `created_at`, then
  the id — and not from wherever the answer happened to list things.
  """

  use ExUnit.Case
  @moduletag :core

  import Mox

  alias BotArmyRpg.Sessions

  @tenant "00000000-0000-0000-0000-000000000099"
  @user "00000000-0000-0000-0000-0000000000aa"

  setup :verify_on_exit!

  setup do
    Application.put_env(:bot_army_rpg, :session_store, BotArmyRpg.SessionStoreMock)

    on_exit(fn -> Application.delete_env(:bot_army_rpg, :session_store) end)

    :ok
  end

  defp store_answers(answer) do
    tenant = @tenant
    Mox.expect(BotArmyRpg.SessionStoreMock, :list, fn ^tenant -> answer end)
  end

  defp window(overrides) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "tenant_id" => @tenant,
        "user_id" => @user,
        "status" => "active",
        "scene_description" => "somewhere",
        "created_at" => "2026-09-01T10:00:00",
        "updated_at" => "2026-09-01T10:00:00"
      },
      overrides
    )
  end

  test "the window is the one this identity touched most recently, not the one listed first" do
    older = window(%{"updated_at" => "2026-09-01T10:00:00", "scene_description" => "older"})
    newer = window(%{"updated_at" => "2026-09-02T10:00:00", "scene_description" => "newer"})

    # Listed older first, which is exactly the order that used to decide.
    store_answers({:ok, [older, newer]})

    assert {:ok, session} = Sessions.active_for(@tenant, @user)
    assert session["scene_description"] == "newer"
  end

  test "two windows touched in the same second are still decided by a fact, not by luck" do
    same = "2026-09-02T10:00:00"

    first =
      window(%{"updated_at" => same, "created_at" => "2026-09-01T10:00:00", "id" => "aaaa"})

    second =
      window(%{"updated_at" => same, "created_at" => "2026-09-01T11:00:00", "id" => "aaaa"})

    store_answers({:ok, [second, first]})

    assert {:ok, session} = Sessions.active_for(@tenant, @user)
    assert session["created_at"] == "2026-09-01T11:00:00"
  end

  test "a window that is someone else's, or no longer open, is not this identity's window" do
    other_user = window(%{"user_id" => "someone-else", "updated_at" => "2026-09-09T10:00:00"})
    ended = window(%{"status" => "ended", "updated_at" => "2026-09-09T10:00:00"})
    mine = window(%{"updated_at" => "2026-09-02T10:00:00", "scene_description" => "mine"})

    store_answers({:ok, [other_user, ended, mine]})

    assert {:ok, session} = Sessions.active_for(@tenant, @user)
    assert session["scene_description"] == "mine"
  end

  test "a window with no user of its own is the window of the caller who names none" do
    anon = window(%{"user_id" => nil, "scene_description" => "the fleet's own"})

    store_answers({:ok, [anon]})

    assert {:ok, session} = Sessions.active_for(@tenant, nil)
    assert session["scene_description"] == "the fleet's own"
  end

  test "no open window is a definite nothing, and not an error" do
    store_answers({:ok, []})

    assert {:error, :no_active_session} = Sessions.active_for(@tenant, @user)
  end

  test "a store error is passed on, not turned into no window" do
    store_answers({:error, :unavailable})

    assert {:error, :unavailable} = Sessions.active_for(@tenant, @user)
  end

  test "an answer that is not a session list is refused, because a raise would never reply" do
    store_answers([window(%{})])

    assert {:error, :bad_store_answer} = Sessions.active_for(@tenant, @user)
  end
end
