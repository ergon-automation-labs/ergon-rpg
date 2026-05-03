defmodule BotArmyRpg.Schemas.Theme do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "rpg_themes" do
    field(:setting, :string)
    field(:tone, :string)
    field(:mechanic, :string)
    field(:vocabulary, :map, default: %{})
    field(:templates, :map, default: %{})
    field(:npc_personas, :map, default: %{})
    field(:is_current, :boolean, default: false)
    field(:changed_by, :string)
    field(:tenant_id, Ecto.UUID)

    timestamps()
  end

  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [
      :setting,
      :tone,
      :mechanic,
      :vocabulary,
      :templates,
      :npc_personas,
      :is_current,
      :changed_by,
      :tenant_id
    ])
    |> validate_required([:setting, :tone, :mechanic, :tenant_id])
  end
end
