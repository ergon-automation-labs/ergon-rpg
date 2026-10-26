defmodule BotArmyRpg.Handlers.TurnPassingTest do
  @moduledoc """
  A turn that lands on a companion has to be taken by somebody.

  The turn engine seats a party in turn order, and a party may hold bots. Nobody can press
  for a companion, so a round that stops on one is a table that does nothing: measured
  2026-10-26 on the live bot — `rpg.turn.start_round` seated `companion_bot` at
  `active_index` 0, replied, and no fact was ever written. The page read the turn as
  "nobody's turn yet" and sat there, which is exactly the report it came from.

  `rpg.turn.next` already played a bot and left the turn on it. Now the engine plays each
  bot actor it meets and hands the turn on, stopping on a turn a player can take, so
  "the next turn" means *the next turn somebody can take*. These tests are about that
  chain: it must play the bot, it must keep the bot's `turn_history` record when it
  advances (the advance is built from a re-read session, not a stale one), and it must
  stop after one round when the whole party is bots.

  The stores are plain process-backed doubles rather than Mox: the chain runs in a
  `Task`, and a double owned by the test process would be reading its own mailbox.
  """

  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyRpg.Handlers.GMHandler

  @tenant "00000000-0000-0000-0000-000000000001"
  @session "00000000-0000-0000-0000-0000000000se"
  @companion "2a417889-a6ab-49e2-8448-6e549fc85926"
  @other_bot "bad12683-eec8-4361-9a05-ba018469a9cd"
  @player "58eb193b-2009-4abc-a830-d305d4294428"

  defmodule SessionStore do
    @moduledoc false
    use Agent

    def start_link(session), do: Agent.start_link(fn -> session end, name: __MODULE__)
    def reset(session), do: Agent.update(__MODULE__, fn _ -> session end)
    def get(_tenant, _session_id), do: {:ok, Agent.get(__MODULE__, & &1)}

    def update(_tenant, _session_id, attrs) do
      Agent.get_and_update(__MODULE__, fn session ->
        merged = Map.merge(session, attrs)
        {{:ok, merged}, merged}
      end)
    end

    def state, do: Agent.get(__MODULE__, & &1)
  end

  defmodule CharacterStore do
    @moduledoc false
    use Agent

    def start_link(characters), do: Agent.start_link(fn -> characters end, name: __MODULE__)

    def get(_tenant, id) do
      case Agent.get(__MODULE__, &Map.get(&1, id)) do
        nil -> {:error, :not_found}
        character -> {:ok, character}
      end
    end

    def update(_tenant, _id, attrs), do: {:ok, attrs}
  end

  defmodule ThemeStore do
    @moduledoc false
    def get_current(_tenant), do: {:ok, %{"name" => "a probe world", "rules" => %{}}}
  end

  defmodule SceneFactStore do
    @moduledoc false
    use Agent

    def start_link(_arg), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    def list_for_session(_tenant, _session_id), do: {:ok, Agent.get(__MODULE__, & &1)}

    def append(fact) do
      Agent.update(__MODULE__, &[fact | &1])
      {:ok, fact}
    end

    def facts, do: Agent.get(__MODULE__, & &1)
  end

  defmodule PartyStore do
    @moduledoc false
    def get_party(_tenant, _user), do: {:error, :not_found}
  end

  setup do
    start_supervised!({SessionStore, session()})
    start_supervised!({CharacterStore, characters()})
    start_supervised!({SceneFactStore, nil})

    Application.put_env(:bot_army_rpg, :session_store, SessionStore)
    Application.put_env(:bot_army_rpg, :character_store, CharacterStore)
    Application.put_env(:bot_army_rpg, :theme_store, ThemeStore)
    Application.put_env(:bot_army_rpg, :scene_fact_store, SceneFactStore)
    Application.put_env(:bot_army_rpg, :party_store, PartyStore)

    on_exit(fn ->
      Application.delete_env(:bot_army_rpg, :session_store)
      Application.delete_env(:bot_army_rpg, :character_store)
      Application.delete_env(:bot_army_rpg, :theme_store)
      Application.delete_env(:bot_army_rpg, :scene_fact_store)
      Application.delete_env(:bot_army_rpg, :party_store)
    end)

    :ok
  end

  defp characters do
    %{
      @companion => %{
        "id" => @companion,
        "name" => "Companion Bot",
        "class" => "Adventurer",
        "bot_id" => "companion_bot",
        "stats" => %{}
      },
      @other_bot => %{
        "id" => @other_bot,
        "name" => "The Bard",
        "class" => "Bard",
        "bot_id" => "llm_bot",
        "stats" => %{}
      },
      @player => %{
        "id" => @player,
        "name" => "Default User",
        "class" => "Adventurer",
        "user_id" => "00000000-0000-0000-0000-000000000002",
        "stats" => %{}
      }
    }
  end

  defp session(character_ids \\ %{@companion => "companion_bot", @player => nil}) do
    %{
      "id" => @session,
      "status" => "active",
      "user_id" => "00000000-0000-0000-0000-000000000002",
      "scene_description" => "a hall with one long table",
      "character_ids" => character_ids,
      "metadata" => %{}
    }
  end

  defp payload do
    %{"tenant_id" => @tenant, "session_id" => @session}
  end

  # The chain runs in a Task (narration is an LLM call), so the table is waited for rather
  # than assumed: the assertion is about where the turn came to rest, not about how fast.
  defp settle(fun, tries \\ 80) do
    Enum.reduce_while(1..tries, nil, fn _, _ ->
      case fun.() do
        {:settled, value} ->
          {:halt, value}

        :waiting ->
          Process.sleep(25)
          {:cont, nil}
      end
    end) || flunk("the table never settled")
  end

  defp turn_state(session), do: get_in(session, ["metadata", "turn_state"])

  test "a round that opens on a companion's turn is played and handed to the player" do
    assert {:ok, %{"current_actor" => %{"type" => "bot", "bot_id" => "companion_bot"}}} =
             GMHandler.handle_turn_start_round(payload())

    session =
      settle(fn ->
        session = SessionStore.state()
        state = turn_state(session)

        if state["active_index"] == 1 do
          {:settled, session}
        else
          :waiting
        end
      end)

    state = turn_state(session)

    # The turn reached the player, not just the next seat.
    assert Enum.at(state["turn_order"], state["active_index"]) == @player

    # And the companion really took its turn: one record, and its words were written.
    assert [record] = state["turn_history"]
    assert record["character_id"] == @companion

    facts = SceneFactStore.facts()
    assert [fact] = facts
    assert fact["source"] == "gm"
    assert fact["session_id"] == @session
    assert is_binary(fact["content"]) and fact["content"] != ""
  end

  test "a party of bots only plays one round and stops" do
    SessionStore.reset(session(%{@companion => "companion_bot", @other_bot => "llm_bot"}))

    assert {:ok, _} = GMHandler.handle_turn_start_round(payload())

    session =
      settle(fn ->
        state = turn_state(SessionStore.state())
        # A round is over when the turn is back at the first seat with the party's turns
        # written down: the chain is bounded by the party's size, so it stops here.
        if state["active_index"] == 0 and length(state["turn_history"] || []) >= 1 do
          {:settled, SessionStore.state()}
        else
          :waiting
        end
      end)

    state = turn_state(session)
    assert Enum.map(state["turn_history"], & &1["character_id"]) == [@other_bot, @companion]

    # One round, not a spin: nothing more arrives after the table stops.
    Process.sleep(150)
    assert length(SceneFactStore.facts()) == 2
  end

  test "a round that opens on the player is left alone" do
    SessionStore.reset(session(%{@player => nil}))

    assert {:ok, %{"current_actor" => %{"type" => "player"}}} =
             GMHandler.handle_turn_start_round(payload())

    Process.sleep(150)

    assert turn_state(SessionStore.state())["active_index"] == 0
    assert SceneFactStore.facts() == []
  end
end
