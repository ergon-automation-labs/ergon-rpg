defmodule BotArmyRpg.Repo.Migrations.CreateHeartbeats do
  @moduledoc """
  The heartbeats table the shared runtime's Heartbeat store writes to.

  This bot's database was created without it, so every Personality heartbeat
  answered `relation "heartbeats" does not exist` — a warning every 30 seconds,
  all day, in a log that operators read. Same shape as the other bots': one row
  per (service, tenant), upserted, so it grows with the fleet and not with time.

  `create_if_not_exists` throughout so re-running the state on a database that
  already has the table changes nothing.
  """
  use Ecto.Migration

  def change do
    create_if_not_exists table(:heartbeats, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:bot_id, :string, null: false)
      add(:service, :string, null: false)
      add(:tenant_id, :uuid, null: false)
      add(:source, :string)
      add(:status, :string, null: false)
      add(:uptime_seconds, :integer)
      add(:last_event_age_ms, :integer)
      add(:sequence, :integer)
      add(:payload, :jsonb)
      add(:recorded_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(unique_index(:heartbeats, [:service, :tenant_id]))
    create_if_not_exists(index(:heartbeats, [:bot_id]))
    create_if_not_exists(index(:heartbeats, [:tenant_id]))
    create_if_not_exists(index(:heartbeats, [:service]))
  end
end
