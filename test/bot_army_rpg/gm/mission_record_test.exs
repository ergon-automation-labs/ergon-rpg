defmodule BotArmyRpg.GM.MissionRecordTest do
  @moduledoc """
  What a finished mission leaves for the one who went on it to tell.

  The record is witness-scoped: the scene, the party as it was named, each turn and the GM's lines,
  and nothing the theme holds back (a persona's backstory, secret, relationships, carried items).
  A letter written from it can only say what the party saw.
  """

  use ExUnit.Case, async: false
  @moduletag :handlers

  alias BotArmyRpg.GM.MissionRecord

  @tenant "00000000-0000-0000-0000-000000000001"

  @theme %{
    "setting" => "Neon Nexus City",
    "npc_personas" => %{
      "fixer" => %{
        "name" => "Mara Voss",
        "title" => "Fixer",
        "bot_assignments" => ["gtd"],
        "backstory" => "BACKSTORY-MARKER",
        "secret" => "SECRET-MARKER",
        "relationships" => %{"x" => "RELATIONSHIP-MARKER"},
        "carries" => ["CARRIES-MARKER"],
        "demeanor" => "DEMEANOR-MARKER"
      }
    }
  }

  defmodule Sessions do
    @moduledoc false
    def list(_tenant), do: {:ok, Application.get_env(:bot_army_rpg, :record_test_sessions, [])}

    def get(_tenant, id) do
      case Enum.find(
             Application.get_env(:bot_army_rpg, :record_test_sessions, []),
             &(&1["id"] == id)
           ) do
        nil -> {:error, :not_found}
        s -> {:ok, s}
      end
    end
  end

  defmodule Characters do
    @moduledoc false
    def get(_tenant, id) do
      case Application.get_env(:bot_army_rpg, :record_test_characters, %{})[id] do
        nil -> {:error, :not_found}
        c -> {:ok, c}
      end
    end
  end

  defmodule Facts do
    @moduledoc false
    def list_for_session(_tenant, id),
      do: {:ok, Application.get_env(:bot_army_rpg, :record_test_facts, %{}) |> Map.get(id, [])}
  end

  defmodule Themes do
    @moduledoc false
    def get_current(_tenant), do: {:ok, Application.get_env(:bot_army_rpg, :record_test_theme)}
  end

  defp turn(character_id, verb, outcome, at),
    do: %{
      "action" => %{"action_type" => verb, "description" => "x acts."},
      "character_id" => character_id,
      "outcome" => outcome,
      "timestamp" => at
    }

  defp session(id, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "user_id" => nil,
        "status" => "ended",
        "ended_at" => "2026-11-21T07:08:41Z",
        "scene_description" => "A rooftop above the Nexus.",
        "character_ids" => %{"c-eir" => "companion_bot", "c-mara" => "gtd_bot"},
        "metadata" => %{
          "turn_state" => %{
            "turn_order" => ["c-eir", "c-mara"],
            # newest first, as the store keeps it
            "turn_history" => [
              turn(
                "c-mara",
                "hack (breach corporate systems or ICE)",
                "success",
                "2026-11-21T07:08:27Z"
              ),
              turn(
                "c-eir",
                "persuade (negotiate with fixers, corps, or gang leaders)",
                "failure",
                "2026-11-21T07:08:20Z"
              )
            ]
          }
        }
      },
      attrs
    )
  end

  setup do
    Application.put_env(:bot_army_rpg, :session_store, Sessions)
    Application.put_env(:bot_army_rpg, :character_store, Characters)
    Application.put_env(:bot_army_rpg, :scene_fact_store, Facts)
    Application.put_env(:bot_army_rpg, :theme_store, Themes)
    Application.put_env(:bot_army_rpg, :record_test_theme, @theme)

    Application.put_env(:bot_army_rpg, :record_test_characters, %{
      "c-eir" => %{"id" => "c-eir", "name" => "Eir", "bot_id" => "companion_bot"},
      "c-mara" => %{"id" => "c-mara", "name" => "The Lorekeeper", "bot_id" => "gtd_bot"}
    })

    Application.put_env(:bot_army_rpg, :record_test_facts, %{
      "m1" => [
        %{
          "content" => "Mara slices the net.",
          "category" => "narration",
          "source" => "gm",
          "created_at" => "2026-11-21T07:08:27Z"
        },
        %{
          "content" => "Eir's pitch falls flat.",
          "category" => "narration",
          "source" => "gm",
          "created_at" => "2026-11-21T07:08:21Z"
        },
        %{
          "content" => "a player said this",
          "category" => "chat",
          "source" => "player",
          "created_at" => "2026-11-21T07:08:22Z"
        }
      ]
    })

    Application.put_env(:bot_army_rpg, :record_test_sessions, [session("m1")])

    on_exit(fn ->
      for k <- [
            :session_store,
            :character_store,
            :scene_fact_store,
            :theme_store,
            :record_test_theme,
            :record_test_characters,
            :record_test_facts,
            :record_test_sessions
          ],
          do: Application.delete_env(:bot_army_rpg, k)
    end)

    :ok
  end

  describe "debrief/1" do
    test "is the scene, the party as named, the turns in the order they happened, and the GM's lines" do
      assert {:ok, d} = MissionRecord.debrief(%{"tenant_id" => @tenant, "session_id" => "m1"})

      assert d["session_id"] == "m1"
      assert d["scene"] == "A rooftop above the Nexus."
      assert d["ended_at"] == "2026-11-21T07:08:41Z"

      assert d["party"] == [
               %{"name" => "Eir", "bot_id" => "companion_bot"},
               %{"name" => "Mara Voss", "bot_id" => "gtd_bot"}
             ]

      assert d["turns"] == [
               %{"round" => 1, "name" => "Eir", "action" => "persuade", "outcome" => "failure"},
               %{"round" => 1, "name" => "Mara Voss", "action" => "hack", "outcome" => "success"}
             ]

      assert d["story"] == ["Eir's pitch falls flat.", "Mara slices the net."]
    end

    test "a second round is round 2" do
      history =
        for {cid, at} <- [
              {"c-mara", "07:08:50Z"},
              {"c-eir", "07:08:45Z"},
              {"c-mara", "07:08:27Z"},
              {"c-eir", "07:08:20Z"}
            ],
            do: turn(cid, "hack (x)", "success", "2026-11-21T" <> at)

      s = put_in(session("m1"), ["metadata", "turn_state", "turn_history"], history)
      Application.put_env(:bot_army_rpg, :record_test_sessions, [s])

      assert {:ok, %{"turns" => turns}} = MissionRecord.debrief(%{"session_id" => "m1"})
      assert Enum.map(turns, & &1["round"]) == [1, 1, 2, 2]
    end

    test "holds nothing the theme keeps back: no backstory, secret, relationships, carried items or demeanor" do
      assert {:ok, d} = MissionRecord.debrief(%{"session_id" => "m1"})
      flat = inspect(d)

      for marker <- ["BACKSTORY", "SECRET", "RELATIONSHIP", "CARRIES", "DEMEANOR"],
          do: refute(flat =~ marker, "#{marker} leaked into the debrief")

      assert Enum.sort(Map.keys(d)) ==
               ~w(ended_at party scene session_id story turns)
    end

    test "only the GM's narration is the story, and a fact with no words is left out" do
      Application.put_env(:bot_army_rpg, :record_test_facts, %{
        "m1" => [
          %{
            "content" => "  ",
            "category" => "narration",
            "source" => "gm",
            "created_at" => "2026-11-21T07:08:21Z"
          },
          %{
            "content" => "kept",
            "category" => "narration",
            "source" => "gm",
            "created_at" => "2026-11-21T07:08:22Z"
          },
          %{"category" => "narration", "source" => "gm", "created_at" => "2026-11-21T07:08:23Z"}
        ]
      })

      assert {:ok, %{"story" => ["kept"]}} = MissionRecord.debrief(%{"session_id" => "m1"})
    end

    test "a table a person plays at is not a mission, and is refused" do
      Application.put_env(:bot_army_rpg, :record_test_sessions, [
        session("p1", %{"user_id" => "00000000-0000-0000-0000-000000000002"})
      ])

      assert {:error, :not_a_mission} = MissionRecord.debrief(%{"session_id" => "p1"})
    end

    test "a mission still running has no debrief yet" do
      Application.put_env(:bot_army_rpg, :record_test_sessions, [
        session("m1", %{"status" => "active"})
      ])

      assert {:error, :still_running} = MissionRecord.debrief(%{"session_id" => "m1"})
    end

    test "a mission that played no turn has nothing to tell" do
      s = put_in(session("m1"), ["metadata", "turn_state", "turn_history"], [])
      Application.put_env(:bot_army_rpg, :record_test_sessions, [s])
      assert {:error, :nothing_happened} = MissionRecord.debrief(%{"session_id" => "m1"})
    end

    test "an unknown session, or no id, is an error, not a crash" do
      assert {:error, :not_found} = MissionRecord.debrief(%{"session_id" => "nope"})
      assert {:error, :session_id_required} = MissionRecord.debrief(%{})
    end

    test "a character the store cannot read is named by its bot, not dropped" do
      Application.put_env(:bot_army_rpg, :record_test_characters, %{})
      assert {:ok, %{"party" => party}} = MissionRecord.debrief(%{"session_id" => "m1"})
      assert Enum.map(party, & &1["name"]) == ["companion_bot", "gtd_bot"]
    end
  end

  describe "recent/1" do
    test "lists the leader's finished missions that played, newest first" do
      older = session("m0", %{"ended_at" => "2026-11-20T10:00:00Z"})

      probe =
        session("probe", %{
          "character_ids" => %{"c-mara" => "gtd_bot"},
          "ended_at" => "2026-11-21T09:00:00Z"
        })

      empty =
        put_in(
          session("empty", %{"ended_at" => "2026-11-21T08:00:00Z"}),
          ["metadata", "turn_state", "turn_history"],
          []
        )

      running = session("run", %{"status" => "active"})
      persons = session("person", %{"user_id" => "u"})

      Application.put_env(:bot_army_rpg, :record_test_sessions, [
        older,
        session("m1"),
        probe,
        empty,
        running,
        persons
      ])

      assert {:ok, %{"missions" => missions}} =
               MissionRecord.recent(%{"leader_bot_id" => "companion_bot"})

      assert Enum.map(missions, & &1["session_id"]) == ["m1", "m0"]
      assert hd(missions)["turns"] == 2
      assert hd(missions)["ended_at"] == "2026-11-21T07:08:41Z"
    end

    test "is bounded by a limit, and by a since time" do
      many =
        for n <- 1..12,
            do:
              session("m#{n}", %{
                "ended_at" => "2026-11-21T07:00:#{String.pad_leading("#{n}", 2, "0")}Z"
              })

      Application.put_env(:bot_army_rpg, :record_test_sessions, many)

      assert {:ok, %{"missions" => ten}} =
               MissionRecord.recent(%{"leader_bot_id" => "companion_bot"})

      assert length(ten) == 10

      assert {:ok, %{"missions" => three}} =
               MissionRecord.recent(%{"leader_bot_id" => "companion_bot", "limit" => 3})

      assert length(three) == 3

      assert {:ok, %{"missions" => late}} =
               MissionRecord.recent(%{
                 "leader_bot_id" => "companion_bot",
                 "since" => "2026-11-21T07:00:09Z"
               })

      assert Enum.map(late, & &1["session_id"]) == ["m12", "m11", "m10"]

      # "since" is exclusive: a mission that ended at that very moment was already told.
      assert {:ok, %{"missions" => exact}} =
               MissionRecord.recent(%{
                 "leader_bot_id" => "companion_bot",
                 "since" => "2026-11-21T07:00:10Z"
               })

      assert Enum.map(exact, & &1["session_id"]) == ["m12", "m11"]
    end

    test "needs a leader" do
      assert {:error, :leader_bot_id_required} = MissionRecord.recent(%{})
    end
  end
end
