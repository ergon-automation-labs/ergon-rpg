defmodule BotArmyRpg.GM.MissionTest do
  @moduledoc """
  A mission is a table that plays without a player: Eir, two crew drawn at random from the
  other bot characters, a scene the GM sets, and a bounded number of rounds.

  The stores are process-backed doubles, as in `turn_passing_test.exs`, because the driver
  runs in a `Task`.
  """

  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyRpg.GM.Mission

  @tenant "00000000-0000-0000-0000-000000000001"

  defmodule SessionStore do
    @moduledoc false
    use Agent

    def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

    def create(payload) do
      session = Map.put(payload, "id", Ecto.UUID.generate())
      Agent.update(__MODULE__, &Map.put(&1, session["id"], session))
      {:ok, session}
    end

    def get(_tenant, id) do
      case Agent.get(__MODULE__, &Map.get(&1, id)) do
        nil -> {:error, :not_found}
        session -> {:ok, session}
      end
    end

    def update(_tenant, id, attrs) do
      Agent.get_and_update(__MODULE__, fn sessions ->
        case Map.fetch(sessions, id) do
          {:ok, session} ->
            merged = Map.merge(session, attrs)
            {{:ok, merged}, Map.put(sessions, id, merged)}

          :error ->
            {{:error, :not_found}, sessions}
        end
      end)
    end

    def all, do: Agent.get(__MODULE__, &Map.values/1)
  end

  defmodule CharacterStore do
    @moduledoc false
    use Agent

    def start_link(characters), do: Agent.start_link(fn -> characters end, name: __MODULE__)
    def list(_tenant), do: {:ok, Agent.get(__MODULE__, & &1)}

    def get(_tenant, id) do
      case Enum.find(Agent.get(__MODULE__, & &1), &(&1["id"] == id)) do
        nil -> {:error, :not_found}
        c -> {:ok, c}
      end
    end

    def get_by_bot_id(_tenant, bot_id) do
      case Enum.find(Agent.get(__MODULE__, & &1), &(&1["bot_id"] == bot_id)) do
        nil -> {:error, :not_found}
        c -> {:ok, c}
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

    def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def list_for_session(_tenant, _id), do: {:ok, Agent.get(__MODULE__, & &1)}

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

  defmodule RaisingThemeStore do
    @moduledoc false
    def get_current(_tenant), do: raise("the theme store fell over")
  end

  defmodule Model do
    @moduledoc false
    def request("llm.prompt.submit", _payload, _opts) do
      Process.sleep(Application.get_env(:bot_army_rpg, :mission_test_model_delay_ms, 0))
      {:ok, %{"completion" => "A rooftop deal goes sideways above the Nexus."}}
    end

    def request(_subject, _payload, _opts), do: {:error, :unavailable}
  end

  defmodule DownModel do
    @moduledoc false
    def request(_subject, _payload, _opts), do: {:error, :timeout}
  end

  defp character(id, bot_id, class),
    do: %{
      "id" => id,
      "name" => "char-#{id}",
      "class" => class,
      "bot_id" => bot_id,
      "stats" => %{}
    }

  defp roster do
    [
      character("c-eir", "companion_bot", "Face"),
      character("c-old", "companion_bot_retired", "Adventurer"),
      character("c-gtd", "gtd_bot", "Scheduler"),
      character("c-llm", "llm_bot", "Bard"),
      character("c-syn", "synapse", "Oracle"),
      character("c-syn2", "synapse", "Oracle"),
      %{
        "id" => "c-abby",
        "name" => "Default User",
        "class" => "Adventurer",
        "user_id" => "00000000-0000-0000-0000-000000000002",
        "stats" => %{}
      }
    ]
  end

  setup do
    start_supervised!(SessionStore)
    start_supervised!({CharacterStore, roster()})
    start_supervised!(SceneFactStore)

    Application.put_env(:bot_army_rpg, :session_store, SessionStore)
    Application.put_env(:bot_army_rpg, :character_store, CharacterStore)
    Application.put_env(:bot_army_rpg, :theme_store, ThemeStore)
    Application.put_env(:bot_army_rpg, :scene_fact_store, SceneFactStore)
    Application.put_env(:bot_army_rpg, :party_store, PartyStore)
    Application.put_env(:bot_army_rpg, :nats_publisher, Model)
    Application.put_env(:bot_army_rpg, :mission_finished_notify, self())

    on_exit(fn ->
      for key <- [
            :session_store,
            :character_store,
            :theme_store,
            :scene_fact_store,
            :party_store,
            :nats_publisher,
            :mission_finished_notify
          ],
          do: Application.delete_env(:bot_army_rpg, key)
    end)

    :ok
  end

  defp settle(fun, tries \\ 200) do
    Enum.reduce_while(1..tries, nil, fn _, _ ->
      case fun.() do
        {:settled, value} ->
          {:halt, value}

        :waiting ->
          Process.sleep(25)
          {:cont, nil}
      end
    end) || flunk("the mission never settled")
  end

  defp ended(session_id) do
    session =
      settle(fn ->
        {:ok, s} = SessionStore.get(@tenant, session_id)
        if s["status"] == "ended", do: {:settled, s}, else: :waiting
      end)

    assert_receive {:mission_finished, ^session_id}, 5_000
    {:ok, session} = SessionStore.get(@tenant, session_id)
    session
  end

  describe "crew/4" do
    test "is drawn from other bots' characters: never the leader, a retired one, or a person" do
      crew = Mission.crew(roster(), "companion_bot", 10, & &1)
      assert Enum.map(crew, & &1["bot_id"]) == ["gtd_bot", "llm_bot", "synapse"]
    end

    test "the draw is the shuffle's, and takes only as many as asked" do
      crew = Mission.crew(roster(), "companion_bot", 2, &Enum.reverse/1)
      assert Enum.map(crew, & &1["bot_id"]) == ["synapse", "llm_bot"]
    end
  end

  describe "start/1" do
    test "seats Eir and two crew, owned by no user, under a scene the GM set" do
      assert {:ok, %{"session_id" => id, "scene" => scene, "party" => party, "rounds" => 5}} =
               Mission.start(%{"tenant_id" => @tenant})

      assert scene == "A rooftop deal goes sideways above the Nexus."
      assert length(party) == 3
      assert Enum.any?(party, &(&1["bot_id"] == "companion_bot"))
      refute Enum.any?(party, &(&1["bot_id"] in ["companion_bot_retired", nil]))

      {:ok, session} = SessionStore.get(@tenant, id)
      assert session["user_id"] == nil
      assert session["scene_description"] == scene
      assert map_size(session["character_ids"]) == 3
      _ = ended(id)
    end

    test "a seed from the operator is the scene, and the GM is not asked" do
      Application.put_env(:bot_army_rpg, :nats_publisher, DownModel)

      assert {:ok, %{"scene" => "a heist at the data vault", "session_id" => id}} =
               Mission.start(%{"tenant_id" => @tenant, "scene" => "a heist at the data vault"})

      _ = ended(id)
    end

    test "a GM that cannot write a scene sends nobody out, and opens no table" do
      Application.put_env(:bot_army_rpg, :nats_publisher, DownModel)

      assert {:error, :timeout} = Mission.start(%{"tenant_id" => @tenant})
      assert SessionStore.all() == []
    end

    test "no character for the leader is a refusal, not a table of crew alone" do
      assert {:error, :not_found} =
               Mission.start(%{"tenant_id" => @tenant, "leader_bot_id" => "nobody_bot"})

      assert SessionStore.all() == []
    end

    test "rounds are bounded: the default, the operator's number, and a ceiling" do
      assert {:ok, %{"rounds" => 5, "session_id" => a}} = Mission.start(%{"tenant_id" => @tenant})

      assert {:ok, %{"rounds" => 3, "session_id" => b}} =
               Mission.start(%{"tenant_id" => @tenant, "rounds" => 3})

      assert {:ok, %{"rounds" => 10, "session_id" => c}} =
               Mission.start(%{"tenant_id" => @tenant, "rounds" => 500})

      assert {:ok, %{"rounds" => 5, "session_id" => d}} =
               Mission.start(%{"tenant_id" => @tenant, "rounds" => 0})

      for id <- [a, b, c, d] do
        Mission.stop(%{"tenant_id" => @tenant, "session_id" => id})
        ended(id)
      end
    end
  end

  describe "the table plays on its own" do
    test "every seat acts once per round, for exactly the rounds asked, then the table ends" do
      {:ok, %{"session_id" => id}} = Mission.start(%{"tenant_id" => @tenant, "rounds" => 2})
      session = ended(id)

      history = get_in(session, ["metadata", "turn_state", "turn_history"])
      assert length(history) == 2 * 3

      by_character = Enum.frequencies_by(history, & &1["character_id"])
      assert Map.values(by_character) == [2, 2, 2]

      assert length(SceneFactStore.facts()) >= 6
    end

    test "stopping ends the table and the driver plays no further turn" do
      Application.put_env(:bot_army_rpg, :mission_test_model_delay_ms, 20)
      on_exit(fn -> Application.delete_env(:bot_army_rpg, :mission_test_model_delay_ms) end)

      {:ok, %{"session_id" => id}} = Mission.start(%{"tenant_id" => @tenant, "rounds" => 10})

      assert {:ok, %{"stopped" => true}} =
               Mission.stop(%{"tenant_id" => @tenant, "session_id" => id})

      session = ended(id)
      played = length(get_in(session, ["metadata", "turn_state", "turn_history"]) || [])
      Process.sleep(300)
      {:ok, later} = SessionStore.get(@tenant, id)
      assert length(get_in(later, ["metadata", "turn_state", "turn_history"]) || []) == played
      assert played < 30
    end

    test "a turn that raises ends the table instead of leaving it running forever" do
      Application.put_env(:bot_army_rpg, :theme_store, RaisingThemeStore)

      {:ok, %{"session_id" => id}} =
        Mission.start(%{"tenant_id" => @tenant, "scene" => "a seeded scene"})

      assert %{"status" => "ended"} = ended(id)
    end

    test "stopping a table that is not there says so" do
      assert {:error, :not_found} =
               Mission.stop(%{"tenant_id" => @tenant, "session_id" => "nope"})
    end
  end
end
