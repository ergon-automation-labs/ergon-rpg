defmodule BotArmyRpg.JobPublisher do
  @moduledoc """
  Test helper: speaks the async job protocol the GM asks the LLM bot in
  (`llm.request.chat` with `async: true`, then `llm.job.status`), from a one-shot answer.

  `answer` is `fn prompt, payload, opts -> outcome end`, and the outcome is one of
  `{:content, text}`, `{:result, map}` (a completed job's whole result), `{:failed, reason}`,
  or `{:submit_error, reason}` (the submit itself is refused). The outcome rides in the job id,
  so the double keeps no state.
  """

  def request(answer, "llm.request.chat", payload, opts) do
    prompt = get_in(payload, ["prompt_context", "prompt"])

    case answer.(prompt, payload, opts) do
      {:submit_error, reason} -> {:error, reason}
      outcome -> {:ok, %{"job_id" => encode(outcome), "status" => "accepted"}}
    end
  end

  def request(_answer, "llm.job.status", %{"job_id" => id}, _opts) do
    case decode(id) do
      {:content, text} ->
        {:ok, %{"ok" => true, "status" => "completed", "result" => %{"content" => text}}}

      {:result, result} ->
        {:ok, %{"ok" => true, "status" => "completed", "result" => result}}

      {:failed, reason} ->
        {:ok, %{"ok" => true, "status" => "failed", "error" => reason}}
    end
  end

  def request(_answer, _subject, _payload, _opts), do: {:error, :no_bridge}

  defp encode(outcome), do: "job:" <> Base.url_encode64(:erlang.term_to_binary(outcome))

  defp decode("job:" <> encoded),
    do: encoded |> Base.url_decode64!() |> :erlang.binary_to_term()
end
