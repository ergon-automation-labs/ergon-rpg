defmodule BotArmyRpg.GM.LlmJobTest do
  @moduledoc """
  The GM asks the LLM bot as an async job and waits for it as long as the job needs.

  A sync prompt starts a 180 s HTTP clock the moment it is sent, and that clock runs while the
  prompt waits behind other callers on the same local model. A job waits in the bot's triage
  queue with no clock running, in the `interactive` lane (above the sieve's `background`), and the
  GM polls for it.
  """

  use ExUnit.Case, async: false
  @moduletag :core

  alias BotArmyRpg.GM.LlmJob

  defmodule Bus do
    @moduledoc false
    # A scripted bus: each call to a subject takes the next scripted reply, the last one repeating.
    use Agent

    def start_link(script),
      do: Agent.start_link(fn -> %{script: script, log: []} end, name: __MODULE__)

    def request(subject, payload, _opts) do
      Agent.get_and_update(__MODULE__, fn state ->
        {replies, rest} =
          case Map.get(state.script, subject, [{:error, :no_bridge}]) do
            [last] -> {last, [last]}
            [next | more] -> {next, more}
          end

        {replies,
         %{
           state
           | script: Map.put(state.script, subject, rest),
             log: [{subject, payload} | state.log]
         }}
      end)
    end

    def log, do: Agent.get(__MODULE__, &Enum.reverse(&1.log))
    def calls(subject), do: Enum.filter(log(), &(elem(&1, 0) == subject))
  end

  @accepted {:ok, %{"job_id" => "j1", "status" => "accepted", "lane" => "interactive"}}
  @pending {:ok, %{"ok" => true, "status" => "pending", "job_id" => "j1"}}

  defp done(content),
    do: {:ok, %{"ok" => true, "status" => "completed", "result" => %{"content" => content}}}

  defp bus(script) do
    start_supervised!({Bus, script})
    Application.put_env(:bot_army_rpg, :nats_publisher, Bus)
    Application.put_env(:bot_army_rpg, :llm_job_poll_ms, 1)

    on_exit(fn ->
      for key <- [:nats_publisher, :llm_job_poll_ms, :llm_source, :llm_job_wait_ms],
          do: Application.delete_env(:bot_army_rpg, key)
    end)
  end

  test "asks as an interactive, local, async job, with the prompt where the bot reads it" do
    bus(%{"llm.request.chat" => [@accepted], "llm.job.status" => [done("A scene.")]})

    assert {:ok, "A scene."} = LlmJob.ask("set the scene")

    assert [{"llm.request.chat", payload}] = Bus.calls("llm.request.chat")
    assert payload["async"] == true
    assert payload["priority"] == "interactive"
    assert payload["source"] == "local_ollama"
    assert payload["prompt_context"] == %{"prompt" => "set the scene"}
  end

  test "waits through every pending answer, never rushing the model" do
    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [@pending, @pending, @pending, done("Finally.")]
    })

    assert {:ok, "Finally."} = LlmJob.ask("x", wait_ms: 5_000)
    assert length(Bus.calls("llm.job.status")) == 4
  end

  test "a job still pending at the end of the budget is a wait that ran out, not an empty scene" do
    bus(%{"llm.request.chat" => [@accepted], "llm.job.status" => [@pending]})

    assert {:error, {:job_wait_exceeded, "j1"}} = LlmJob.ask("x", wait_ms: 30)
  end

  test "a status request that fails is retried, not read as the job failing" do
    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [{:error, :timeout}, {:error, :timeout}, done("Back.")]
    })

    assert {:ok, "Back."} = LlmJob.ask("x", wait_ms: 5_000)
  end

  test "a job the bot reports failed is an error carrying its reason" do
    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [{:ok, %{"status" => "failed", "error" => ":timeout"}}]
    })

    assert {:error, {:llm_failed, ":timeout"}} = LlmJob.ask("x")
  end

  test "the bot's canned fallback is never a scene" do
    degraded = %{
      "content" => "I am unable to answer right now.",
      "degraded" => true,
      "degrade_reason" => ":no_providers_available",
      "provider" => "local_fallback"
    }

    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [{:ok, %{"status" => "completed", "result" => degraded}}]
    })

    assert {:error, {:degraded, ":no_providers_available"}} = LlmJob.ask("x")
  end

  test "an answer with an error, or with no words, is a failure and not prose" do
    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [
        {:ok, %{"status" => "completed", "result" => %{"error" => ":empty_prompt"}}}
      ]
    })

    assert {:error, {:llm_error, ":empty_prompt"}} = LlmJob.ask("x")
  end

  test "blank content is not an answer" do
    bus(%{"llm.request.chat" => [@accepted], "llm.job.status" => [done("   ")]})
    assert {:error, :unreadable_reply} = LlmJob.ask("x")
  end

  test "a submit that is refused or unreachable is an error, and nothing is polled" do
    bus(%{"llm.request.chat" => [{:error, :no_bridge}]})
    assert {:error, :no_bridge} = LlmJob.ask("x")
    assert Bus.calls("llm.job.status") == []
  end

  test "a job the bot has lost is an error, not an endless wait" do
    bus(%{
      "llm.request.chat" => [@accepted],
      "llm.job.status" => [{:ok, %{"ok" => false, "error" => "job_not_found"}}]
    })

    assert {:error, :job_lost} = LlmJob.ask("x", wait_ms: 5_000)
  end

  test "the source is configuration: unset, the request names none" do
    bus(%{"llm.request.chat" => [@accepted], "llm.job.status" => [done("ok")]})
    Application.put_env(:bot_army_rpg, :llm_source, nil)

    assert {:ok, "ok"} = LlmJob.ask("x")
    assert [{_, payload}] = Bus.calls("llm.request.chat")
    refute Map.has_key?(payload, "source")
  end

  test "the default budget is minutes, not seconds" do
    assert LlmJob.default_wait_ms() >= 600_000
  end
end
