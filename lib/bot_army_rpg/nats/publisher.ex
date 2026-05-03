defmodule BotArmyRpg.NATS.Publisher do
  @moduledoc """
  NATS event publisher for the RPG bot.

  Derives the NATS subject from the event type and publishes
  via BotArmyRuntime.NATS.Publisher.
  """

  require Logger

  def publish(event_name, payload, opts \\ []) do
    subject = derive_subject(event_name)
    event = BotArmyRpg.EventBuilder.build_event(event_name, payload, opts)

    case BotArmyRuntime.NATS.Publisher.publish(subject, event) do
      {:ok, _} ->
        Logger.debug("[RPG Publisher] Published #{event_name} to #{subject}")
        :ok

      {:error, reason} ->
        Logger.warning("[RPG Publisher] Failed to publish #{event_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp derive_subject(event_name) do
    case event_name do
      "rpg.character.created" -> "events.rpg.character.created"
      "rpg.character.updated" -> "events.rpg.character.updated"
      "rpg.session.started" -> "events.rpg.session.started"
      "rpg.session.paused" -> "events.rpg.session.paused"
      "rpg.session.ended" -> "events.rpg.session.ended"
      "rpg.scene.fact.added" -> "events.rpg.scene.fact.added"
      "rpg.error" -> "events.rpg.error"
      _ -> "events.rpg.#{event_name}"
    end
  end
end
