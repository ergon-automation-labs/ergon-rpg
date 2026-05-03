defmodule BotArmyRpg.EventBuilder do
  @moduledoc """
  Shared event envelope construction for RPG bot handlers.
  """

  def build_event(event_name, payload, opts \\ []) do
    %{
      "event" => event_name,
      "event_id" => opts[:event_id] || UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_rpg",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => opts[:triggered_by] || "rpg.bot",
      "schema_version" => "1.0",
      "tenant_id" => opts[:tenant_id],
      "user_id" => opts[:user_id],
      "payload" => payload
    }
  end

  def build_error(triggered_by_event_id, reason, message, opts \\ []) do
    payload = %{
      "error" => message,
      "reason" => inspect(reason),
      "triggered_by_event_id" => triggered_by_event_id
    }

    build_event("rpg.error", payload, opts)
  end
end
