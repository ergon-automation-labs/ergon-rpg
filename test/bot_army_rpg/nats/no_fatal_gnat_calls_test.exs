defmodule BotArmyRpg.NoFatalGnatCallsTest do
  @moduledoc """
  Regression guard for the duplicate-subscription defect measured 2026-10-13.

  Five RPG processes (the Consumer and four subscribers, including the one that
  awards XP) subscribed with a bare `Gnat.sub/3` on every `{:nats, :connected}` and
  never unsubscribed. The air<->mini leaf had flapped 8 times, so
  `rpg.character.create` had accumulated **112** live subscriptions: one request
  ran the handler once per subscription and minted the same character repeatedly.
  `events.gtd.task.completed` was multiplied the same way, which means XP was
  awarded more than once per task.

  gnat 1.13 also matches its socket write as `{:ok, _}` inside `Gnat.handle_call/3`
  (lib/gnat.ex:492): a link the broker has just dropped makes the write return
  `{:error, :einval}` and crashes the Gnat connection process, taking every caller
  blocked in `GenServer.call/3` with it.

  The runtime now offers `Connection.subscribe/1` (durable: the subject list lives
  in a Registry and every new link re-subscribes it, with `Registry.register/3`
  replacing rather than appending) plus the non-fatal `Connection.publish/4`,
  `Connection.unsub/3`, and `Connection.safe_sub/3`. This test is what keeps a new
  bare `Gnat.sub` from creeping back in — it would look entirely reasonable in
  review.
  """
  use ExUnit.Case, async: true

  @moduletag :nats

  @lib Path.expand("../../lib", __DIR__)
  @forbidden ~w(Gnat.pub Gnat.unsub Gnat.sub)

  test "no RPG source file calls bare Gnat pub/unsub/sub" do
    offenders =
      @lib
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _n} ->
          String.contains?(line, @forbidden) and not String.starts_with?(String.trim(line), "#")
        end)
        |> Enum.map(fn {line, n} ->
          "#{Path.relative_to(path, Path.expand("../..", __DIR__))}:#{n}: #{String.trim(line)}"
        end)
      end)

    assert offenders == [],
           """
           These call sites can crash the Gnat connection process and take every
           caller in GenServer.call/3 with them. Use the runtime wrapper:

             Gnat.pub(conn, subject, payload, opts) -> Connection.publish(conn, subject, payload, opts)
             Gnat.unsub(conn, sid, opts)            -> Connection.unsub(conn, sid, opts)
             Gnat.sub(conn, pid, subject)           -> Connection.safe_sub(conn, pid, subject)

           Subscribe with the durable Connection.subscribe/1 instead of a raw sid: the
           registration replaces on re-register and survives a replaced link, so a
           flapping broker can neither darken the bot nor multiply its subscriptions.

           Offenders:
           #{Enum.join(offenders, "\n")}
           """
  end
end
