defmodule BotArmyRpg.Handlers.ReconGateTest do
  use ExUnit.Case
  @moduletag :integration

  import ExUnit.Assertions
  require Logger

  @tenant_id "00000000-0000-0000-0000-000000000001"
  @user_id "00000000-0000-0000-0000-000000000002"
  @category "job_search"

  setup do
    # Clean up any prior quests in this test category
    {:ok, tenant_id: @tenant_id, user_id: @user_id, category: @category}
  end

  test "recon gate blocks quest creation when failure rate >= 60%", %{
    tenant_id: tenant_id,
    user_id: user_id,
    category: category
  } do
    # Setup: create character
    {:ok, _character} =
      BotArmyRpg.CharacterStore.create(%{
        "user_id" => user_id,
        "tenant_id" => tenant_id,
        "name" => "Test Character"
      })

    # Create 6 completed quests: 4 failures + 2 successes (66% failure rate)
    insert_test_quests(tenant_id, category, [
      {0.1, "catastrophic_failure"},
      {0.2, "catastrophic_failure"},
      {0.25, "catastrophic_failure"},
      {0.28, "catastrophic_failure"},
      {0.7, "full_success"},
      {0.8, "full_success"}
    ])

    # Wait a moment for ConsequenceEngine to process
    Process.sleep(500)

    # Create a recon task manually (simulating ConsequenceEngine response)
    recon_payload = %{
      "title" => "Recon: Job Search",
      "description" => "Test recon task",
      "labels" => ["task_type:recon", "category:#{category}"],
      "source_metadata" => %{"generated_by" => "consequence_engine"},
      "tenant_id" => tenant_id,
      "user_id" => user_id
    }

    {:ok, recon_task} =
      BotArmyRuntime.NATS.Publisher.request("bridge.task.create", recon_payload, timeout_ms: 5000)

    recon_task_id = get_in(recon_task, ["data", "id"])
    assert recon_task_id, "Recon task should be created"

    # Now try to create a new quest - should be blocked by recon gate
    quest_payload = %{
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "payload" => %{
        "gtd_task" => %{
          "id" => Ecto.UUID.generate(),
          "title" => "Apply to job",
          "source_category" => category
        },
        "source_category" => category
      }
    }

    result = BotArmyRpg.Handlers.QuestHandler.handle_create(quest_payload)

    assert {:error, %{"reason" => "recon_required", "task_id" => returned_task_id}} = result
    assert returned_task_id == recon_task_id
  end

  test "recon task includes failure analysis with patterns and hints", %{
    tenant_id: tenant_id,
    category: category
  } do
    # Create test quests with clear failure patterns
    insert_test_quests(tenant_id, category, [
      {0.1, "catastrophic_failure"},
      {0.15, "catastrophic_failure"},
      {0.2, "catastrophic_failure"},
      {0.25, "catastrophic_failure"},
      {0.8, "full_success"}
    ])

    # Query completed quests
    quests = BotArmyRpg.QuestStore.list_completed_by_category(tenant_id, category, 10)
    assert length(quests) >= 5

    # Run FailureAnalyzer
    analysis = BotArmyRpg.FailureAnalyzer.analyze(quests, category)

    # Verify analysis structure
    assert analysis["version"] == "1.0"
    assert analysis["category"] == category
    assert analysis["window"]["total"] >= 5
    assert analysis["window"]["failures"] >= 4

    # Verify patterns detected
    patterns = analysis["patterns"]
    assert Enum.any?(patterns, fn p -> p["type"] == "catastrophic_dominant" end)
    assert Enum.any?(patterns, fn p -> p["type"] == "consecutive_streak" end)

    # Verify prescriptive hints
    hints = analysis["prescriptive_hints"]
    assert length(hints) > 0

    catastrophic_hint =
      Enum.find(hints, fn h -> h["pattern"] == "catastrophic_dominant" end)

    assert catastrophic_hint
    assert String.contains?(catastrophic_hint["action"], ["decomposition", "scope"])
    assert String.contains?(catastrophic_hint["why"], ["fundamental", "misaligned"])
  end

  test "quest creation succeeds when no recon task pending", %{
    tenant_id: tenant_id,
    user_id: user_id,
    category: category
  } do
    # Setup: create character
    {:ok, _character} =
      BotArmyRpg.CharacterStore.create(%{
        "user_id" => user_id,
        "tenant_id" => tenant_id,
        "name" => "Test Character"
      })

    # Create just 2 quests (no failure rate threshold)
    insert_test_quests(tenant_id, category, [
      {0.1, "catastrophic_failure"},
      {0.8, "full_success"}
    ])

    # Try to create a new quest - should succeed (no recon required)
    quest_payload = %{
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "payload" => %{
        "gtd_task" => %{
          "id" => Ecto.UUID.generate(),
          "title" => "Apply to job",
          "source_category" => category
        },
        "source_category" => category
      }
    }

    result = BotArmyRpg.Handlers.QuestHandler.handle_create(quest_payload)

    assert {:ok, created_quest} = result
    assert created_quest["title"] == "Apply to job"
    assert created_quest["source_category"] == category
  end

  # Helper: insert test quests directly into database
  defp insert_test_quests(tenant_id, category, outcomes) do
    Enum.each(outcomes, fn {outcome_score, success_band} ->
      quest_attrs = %{
        "id" => Ecto.UUID.generate(),
        "character_id" => Ecto.UUID.generate(),
        "title" => "Test Quest",
        "description" => "Integration test quest",
        "outcome_score" => outcome_score,
        "success_band" => success_band,
        "source_category" => category,
        "status" => "completed",
        "tenant_id" => tenant_id,
        "user_id" => Ecto.UUID.generate()
      }

      BotArmyRpg.Repo.insert(
        BotArmyRpg.Schemas.Quest.changeset(%BotArmyRpg.Schemas.Quest{}, quest_attrs),
        on_conflict: :nothing
      )
    end)
  end
end
