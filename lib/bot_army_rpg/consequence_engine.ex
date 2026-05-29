defmodule BotArmyRpg.ConsequenceEngine do
  @moduledoc """
  Watches quest outcomes and triggers consequences (training suggestions, recon requirements, etc).

  Subscribes to rpg.quest.completed events. When a failure pattern is detected
  (outcome_score < 0.3), emits a training consequence:
  - Creates a GTD training task
  - Triggers terrain skill suggestion
  - Publishes rpg.consequence.triggered event

  Consequences are throttled: at most one per category per 48 hours (Phase 3).
  """

  use GenServer
  require Logger

  alias BotArmyRuntime.NATS.{Connection, Publisher}
  alias BotArmyCore.NATS.Decoder

  @reconnect_delay_ms 5_000

  @category_to_skill %{
    "job_search" => "terrain_daily_system_challenge",
    "code_review" => "terrain_daily_system_challenge",
    "planning" => "terrain_daily_system_challenge",
    "fitness" => nil,
    "chore" => nil
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[ConsequenceEngine] Starting")
    {:ok, %{subscriptions: [], conn: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        Connection.subscribe_to_status()

        Logger.info(
          "[ConsequenceEngine] Connected to NATS, subscribing to quest completion events"
        )

        subscriptions =
          ["rpg.quest.completed"]
          |> Enum.map(fn subject ->
            case Gnat.sub(conn, self(), subject) do
              {:ok, sub} ->
                Logger.info("[ConsequenceEngine] Subscribed to #{subject}")
                sub

              {:error, reason} ->
                Logger.error(
                  "[ConsequenceEngine] Failed to subscribe to #{subject}: #{inspect(reason)}"
                )

                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

      {:error, _reason} ->
        Logger.warning("[ConsequenceEngine] NATS connection not ready, will retry")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    Logger.debug("[ConsequenceEngine] Received event on #{msg.topic}")

    with {:ok, decoded} <- Decoder.decode(msg.body),
         category when is_binary(category) <- Map.get(decoded, "source_category"),
         tenant_id when is_binary(tenant_id) <- Map.get(decoded, "tenant_id") do
      # Check for single-quest failure (training suggestion)
      with {:ok, failure_pattern} <- detect_failure_pattern(decoded),
           true <- failure_pattern do
        :ok = process_consequence(decoded, category)
      else
        _ -> :ok
      end

      # Check for rolling window failure rate (recon requirement)
      :ok = check_recon_trigger(decoded, category, tenant_id)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp detect_failure_pattern(quest) do
    case Map.get(quest, "outcome_score") do
      score when is_float(score) and score < 0.3 ->
        {:ok, true}

      _ ->
        {:ok, false}
    end
  end

  defp process_consequence(quest, category) do
    tenant_id = Map.get(quest, "tenant_id")
    user_id = Map.get(quest, "user_id")

    with :ok <- check_cooldown(),
         {:ok, _task} <- create_training_task(category, tenant_id, user_id),
         :ok <- trigger_skill_suggestion(category, tenant_id),
         :ok <- emit_consequence_event(quest, category, tenant_id, user_id) do
      Logger.info("[ConsequenceEngine] Training consequence triggered for category: #{category}")
      :ok
    else
      error ->
        Logger.warning("[ConsequenceEngine] Consequence failed: #{inspect(error)}")
        error
    end
  end

  defp check_cooldown do
    # In-memory cooldown check - in production, would use Redis/ETS for durability
    # For now, always allow (cooldown would be added in Phase 3)
    :ok
  end

  defp create_training_task(category, tenant_id, user_id) do
    title = "Training: #{humanize_category(category)}"
    labels = ["task_type:training", "consequence:true", "category:#{category}"]

    payload = %{
      "title" => title,
      "labels" => labels,
      "source_metadata" => %{
        "generated_by" => "consequence_engine",
        "trigger_pattern" => "failure_pattern_detected",
        "category" => category
      },
      "tenant_id" => tenant_id,
      "user_id" => user_id
    }

    Logger.debug("[ConsequenceEngine] Creating training task: #{title}")

    case Publisher.request("bridge.task.create", payload, timeout_ms: 5000) do
      {:ok, %{"data" => task}} -> {:ok, task}
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end

  defp trigger_skill_suggestion(category, tenant_id) do
    case Map.get(@category_to_skill, category) do
      nil ->
        Logger.debug("[ConsequenceEngine] No skill mapping for category: #{category}")
        :ok

      skill_slug ->
        payload = %{
          "tenant_id" => tenant_id,
          "query" => "improve #{category} skills"
        }

        Logger.debug("[ConsequenceEngine] Triggering skill: #{skill_slug}")

        case Publisher.publish(
               "bot.army.skills.command.#{skill_slug}",
               payload
             ) do
          :ok -> :ok
          error -> error
        end
    end
  end

  defp emit_consequence_event(quest, category, tenant_id, user_id) do
    event = %{
      "type" => "training_suggested",
      "category" => category,
      "quest_id" => Map.get(quest, "id"),
      "outcome_score" => Map.get(quest, "outcome_score"),
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "triggered_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Publisher.publish("rpg.consequence.triggered", event) do
      :ok -> :ok
      error -> error
    end
  end

  defp check_recon_trigger(quest, category, tenant_id) do
    user_id = Map.get(quest, "user_id")

    quests = BotArmyRpg.QuestStore.list_completed_by_category(tenant_id, category, 10)
    failures = Enum.count(quests, fn q -> q.outcome_score < 0.3 end)

    if length(quests) >= 5 and failures / length(quests) >= 0.6 do
      failure_analysis = BotArmyRpg.FailureAnalyzer.analyze(quests, category)
      create_recon_task_if_none_pending(category, tenant_id, user_id, failure_analysis)
    else
      :ok
    end
  rescue
    _ ->
      Logger.debug("[ConsequenceEngine] Recon check skipped (DB unavailable)")
      :ok
  end

  defp create_recon_task_if_none_pending(category, tenant_id, user_id, failure_analysis) do
    case check_existing_recon(category, tenant_id) do
      {:ok, nil} ->
        # No pending recon task, create one
        create_recon_task(category, tenant_id, user_id, failure_analysis)

      {:ok, _existing_task} ->
        # Already have pending recon task in this category
        Logger.debug("[ConsequenceEngine] Recon task already pending for category: #{category}")
        :ok

      error ->
        Logger.warning("[ConsequenceEngine] Recon check failed: #{inspect(error)}")
        error
    end
  end

  defp check_existing_recon(category, tenant_id) do
    payload = %{
      "labels" => ["task_type:recon", "category:#{category}"],
      "status" => ["active", "next_action", "claimed"],
      "tenant_id" => tenant_id
    }

    case Publisher.request("bridge.task.list", payload, timeout_ms: 3000) do
      {:ok, %{"data" => tasks}} when is_list(tasks) and tasks != [] ->
        {:ok, List.first(tasks)}

      {:ok, %{"data" => []}} ->
        {:ok, nil}

      {:ok, _response} ->
        {:ok, nil}

      error ->
        error
    end
  rescue
    _ -> {:ok, nil}
  end

  defp create_recon_task(category, tenant_id, user_id, failure_analysis) do
    title = "Recon: #{humanize_category(category)}"

    labels = ["task_type:recon", "consequence:true", "category:#{category}"]

    description = build_recon_description(category, failure_analysis)

    payload = %{
      "title" => title,
      "description" => description,
      "labels" => labels,
      "source_metadata" => %{
        "generated_by" => "consequence_engine",
        "trigger_pattern" => "failure_rate_exceeded",
        "category" => category,
        "failure_analysis" => failure_analysis
      },
      "tenant_id" => tenant_id,
      "user_id" => user_id
    }

    Logger.info("[ConsequenceEngine] Creating recon task for category: #{category}")

    case Publisher.request("bridge.task.create", payload, timeout_ms: 5000) do
      {:ok, %{"data" => task}} ->
        emit_recon_consequence_event(category, tenant_id, user_id, task, failure_analysis)

      {:ok, response} ->
        emit_recon_consequence_event(category, tenant_id, user_id, response, failure_analysis)

      error ->
        Logger.error("[ConsequenceEngine] Failed to create recon task: #{inspect(error)}")
        error
    end
  end

  defp emit_recon_consequence_event(category, tenant_id, user_id, task, failure_analysis) do
    event = %{
      "type" => "recon_required",
      "category" => category,
      "task_id" => Map.get(task, "id"),
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "failure_analysis" => failure_analysis,
      "triggered_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Publisher.publish("rpg.consequence.triggered", event) do
      :ok ->
        Logger.info("[ConsequenceEngine] Recon requirement triggered for category: #{category}")
        :ok

      error ->
        error
    end
  end

  defp build_recon_description(category, failure_analysis) do
    window = Map.get(failure_analysis, "window", %{})
    rate = Map.get(window, "rate", 0.0)
    total = Map.get(window, "total", 0)
    patterns = Map.get(failure_analysis, "patterns", [])
    hints = Map.get(failure_analysis, "prescriptive_hints", [])

    patterns_section = format_patterns(patterns)
    hints_section = format_hints(hints)

    """
    ## Reconnaissance Required: #{humanize_category(category)}

    **Failure rate: #{Float.round(rate * 100, 0)}% in last #{total} missions**

    ### What the analysis found

    #{patterns_section}

    ### What to research

    #{hints_section}

    ### How to clear this gate

    Complete this task once you've gathered enough intelligence to attempt this category differently.
    Mark it done when you have a concrete plan, not just when time has passed.

    ---
    _Analysis stored in source_metadata.failure_analysis for after action review._
    """
  end

  defp format_patterns(patterns) do
    patterns
    |> Enum.map(fn pattern ->
      type = Map.get(pattern, "type", "unknown")
      severity = Map.get(pattern, "severity", "unknown")

      human_pattern =
        case type do
          "catastrophic_dominant" ->
            "Most attempts end in catastrophic failure — something fundamental is misaligned"

          "complication_dominant" ->
            "Most attempts hit complications — you're close but being derailed by blockers"

          "consecutive_streak" ->
            "Consecutive failures in a row — the current strategy is broken"

          "declining_trend" ->
            "Performance is getting worse over time — current approach is actively compounding the problem"

          "rapid_retry" ->
            "Retrying within hours of failures — frustration-driven attempts rarely succeed"

          "improving_trend" ->
            "Performance is improving — maintain momentum but protect against regression"

          _ ->
            "Pattern detected: #{type}"
        end

      "- **#{type}** (severity: #{severity}): #{human_pattern}"
    end)
    |> Enum.join("\n")
  end

  defp format_hints(hints) do
    hints
    |> Enum.map_join("\n\n", fn hint ->
      action = Map.get(hint, "action", "")
      why = Map.get(hint, "why", "")

      "**#{action}**\n> #{why}"
    end)
  end

  defp humanize_category(category) do
    category
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
