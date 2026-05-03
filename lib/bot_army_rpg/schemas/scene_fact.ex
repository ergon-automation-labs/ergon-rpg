defmodule BotArmyRpg.Schemas.SceneFact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "rpg_scene_facts" do
    field(:session_id, Ecto.UUID)
    field(:content, :string)
    field(:category, :string, default: "observation")
    field(:source, :string, default: "gm")
    field(:tenant_id, Ecto.UUID)
    field(:user_id, Ecto.UUID)

    timestamps()
  end

  def changeset(scene_fact, attrs) do
    scene_fact
    |> cast(attrs, [:session_id, :content, :category, :source, :tenant_id, :user_id])
    |> validate_required([:session_id, :content, :tenant_id])
  end
end
