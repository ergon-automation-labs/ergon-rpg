defmodule BotArmyRpg.GM.LlmJob do
  @moduledoc """
  Asks the LLM bot for the GM's words as an async job, and waits as long as the job needs.

  A sync `llm.prompt.submit` starts an HTTP clock the moment it is sent, and that clock runs
  while the prompt waits behind other callers on the same local model: measured 2026-11-20, the
  GM's scene prompt timed out at 180 s twice while the RSS sieve's calls on the same model
  answered every few seconds. A job (`llm.request.chat` with `async: true`) waits in the bot's
  triage queue with no clock running, in the `interactive` lane above the sieve's `background`,
  and is answered through `llm.job.status`, which is polled here.

  The bot's canned fallback (`degraded: true`) is never prose: the GM refuses it by name.
  Where the words are written is configuration: `config :bot_army_rpg, :llm_source` (default
  `"local_ollama"`; `nil` walks the default chain), `:llm_job_poll_ms`, and `:llm_job_wait_ms`.
  """

  require Logger

  @submit "llm.request.chat"
  @status "llm.job.status"
  @default_wait_ms 900_000
  @default_poll_ms 2_000
  @submit_timeout_ms 10_000
  @status_timeout_ms 5_000

  @doc "How long the GM waits for a job when the caller names no budget."
  @spec default_wait_ms() :: pos_integer()
  def default_wait_ms,
    do: Application.get_env(:bot_army_rpg, :llm_job_wait_ms, @default_wait_ms)

  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(prompt, opts \\ []) when is_binary(prompt) do
    deadline = now_ms() + Keyword.get(opts, :wait_ms, default_wait_ms())

    with {:ok, job_id} <- submit(prompt),
         {:ok, result} <- await(job_id, deadline) do
      read(result)
    end
  end

  defp submit(prompt) do
    payload =
      with_source(%{
        "async" => true,
        "priority" => "interactive",
        "prompt_context" => %{"prompt" => prompt}
      })

    case publisher().request(@submit, payload, timeout_ms: @submit_timeout_ms) do
      {:ok, %{"job_id" => job_id}} when is_binary(job_id) ->
        {:ok, job_id}

      {:ok, %{"error" => reason}} ->
        {:error, {:llm_refused, reason}}

      {:ok, _other} ->
        {:error, :unreadable_reply}

      {:error, reason} ->
        Logger.warning("[GM.LlmJob] The job was not accepted: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp await(job_id, deadline) do
    case publisher().request(@status, %{"job_id" => job_id}, timeout_ms: @status_timeout_ms) do
      {:ok, %{"status" => "completed", "result" => result}} when is_map(result) ->
        {:ok, result}

      {:ok, %{"status" => "failed"} = job} ->
        {:error, {:llm_failed, job["error"]}}

      {:ok, %{"error" => "job_not_found"}} ->
        {:error, :job_lost}

      {:ok, _still_going} ->
        wait_or_give_up(job_id, deadline)

      {:error, reason} ->
        Logger.warning("[GM.LlmJob] Status of #{job_id} unread: #{inspect(reason)}; asking again")
        wait_or_give_up(job_id, deadline)
    end
  end

  defp wait_or_give_up(job_id, deadline) do
    if now_ms() >= deadline do
      {:error, {:job_wait_exceeded, job_id}}
    else
      Process.sleep(poll_ms())
      await(job_id, deadline)
    end
  end

  defp read(%{"degraded" => true} = result), do: {:error, {:degraded, result["degrade_reason"]}}

  defp read(%{"provider" => "local_fallback"} = result),
    do: {:error, {:degraded, result["degrade_reason"]}}

  defp read(%{"error" => reason}), do: {:error, {:llm_error, reason}}

  defp read(%{"content" => content}) when is_binary(content) do
    case String.trim(content) do
      "" -> {:error, :unreadable_reply}
      _ -> {:ok, content}
    end
  end

  defp read(_result), do: {:error, :unreadable_reply}

  defp with_source(payload) do
    case Application.get_env(:bot_army_rpg, :llm_source, "local_ollama") do
      source when is_binary(source) and source != "" -> Map.put(payload, "source", source)
      _ -> payload
    end
  end

  defp poll_ms, do: Application.get_env(:bot_army_rpg, :llm_job_poll_ms, @default_poll_ms)
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp publisher do
    Application.get_env(:bot_army_rpg, :nats_publisher, BotArmyLibraryRuntime.NATS.Publisher)
  end
end
