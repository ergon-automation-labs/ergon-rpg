defmodule BotArmyRpg.Schemas.Quest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "rpg_quests" do
    field(:character_id, Ecto.UUID)
    field(:title, :string)
    field(:description, :string)
    field(:narrative_framing, :string)
    field(:priority, :string, default: "normal")
    field(:status, :string, default: "active")
    field(:progress, :map, default: %{})
    field(:rewards, :map, default: %{})
    field(:linked_gtd_id, Ecto.UUID)
    field(:success_band, :string)
    field(:dice_roll, :map)
    field(:outcome_score, :float)
    field(:source_category, :string)
    field(:failure_analysis, :map)

    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [
      :character_id,
      :title,
      :description,
      :narrative_framing,
      :priority,
      :status,
      :progress,
      :rewards,
      :linked_gtd_id,
      :success_band,
      :dice_roll,
      :outcome_score,
      :source_category,
      :failure_analysis,
      :tenant_id,
      :user_id
    ])
    |> validate_required([:character_id, :title, :tenant_id])
  end
end
