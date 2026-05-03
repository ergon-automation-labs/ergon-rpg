defmodule BotArmyRpg.ThemeStore do
  use GenServer
  require Logger

  import Ecto.Query

  alias BotArmyRpg.Schemas.Theme

  @server __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def set_current(tenant_id, theme_data, changed_by),
    do: GenServer.call(@server, {:set_current, tenant_id, theme_data, changed_by})

  def get_current(tenant_id),
    do: GenServer.call(@server, {:get_current, tenant_id})

  def list(tenant_id),
    do: GenServer.call(@server, {:list, tenant_id})

  def clear,
    do: GenServer.call(@server, :clear)

  @impl true
  def init(_opts) do
    Logger.info("[ThemeStore] Starting")

    state =
      try do
        themes = BotArmyRpg.Repo.all(Theme)
        current = find_current(themes)
        %{current: current}
      rescue
        _ ->
          Logger.warning("[ThemeStore] Database unavailable, starting empty")
          %{current: nil}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:set_current, tenant_id, theme_data, changed_by}, _from, state) do
    tenant_uuid = convert_to_uuid(tenant_id)

    changeset =
      Theme.changeset(%Theme{}, %{
        setting: theme_data["setting"],
        tone: theme_data["tone"],
        mechanic: theme_data["mechanic"],
        vocabulary: Map.get(theme_data, "vocabulary", %{}),
        templates: Map.get(theme_data, "templates", %{}),
        npc_personas: Map.get(theme_data, "npc_personas", %{}),
        is_current: true,
        changed_by: changed_by,
        tenant_id: tenant_uuid
      })

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:clear_previous, fn repo, _ ->
        from(t in Theme,
          where: t.tenant_id == ^tenant_uuid and t.is_current == true,
          update: [set: [is_current: false]]
        )
        |> repo.update_all([])
      end)
      |> Ecto.Multi.run(:insert_new, fn repo, _ ->
        repo.insert(changeset)
      end)
      |> BotArmyRpg.Repo.transaction()

    case result do
      {:ok, %{insert_new: db_theme}} ->
        theme_map = schema_to_map(db_theme)
        new_state = %{state | current: theme_map}
        Logger.info("[ThemeStore] Theme changed to #{theme_map["setting"]}/#{theme_map["tone"]}")

        publish_theme_broadcast(theme_map)
        publish_theme_event(theme_map)

        {:reply, {:ok, theme_map}, new_state}

      {:error, step, changeset, _} ->
        Logger.error("[ThemeStore] Failed to set theme at #{step}: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset_error_reason(changeset)}, state}
    end
  end

  @impl true
  def handle_call({:get_current, tenant_id}, _from, state) do
    case state.current do
      nil ->
        {:reply, {:error, :not_found}, state}

      theme_map ->
        if theme_map["tenant_id"] == convert_to_uuid(tenant_id) do
          {:reply, {:ok, theme_map}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:list, tenant_id}, _from, state) do
    tenant_uuid = convert_to_uuid(tenant_id)

    themes =
      try do
        Theme
        |> Ecto.Query.where(tenant_id: ^tenant_uuid)
        |> BotArmyRpg.Repo.all()
        |> Enum.map(&schema_to_map/1)
      rescue
        _ -> []
      end

    {:reply, {:ok, themes}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(Theme)
    {:reply, :ok, %{current: nil}}
  end

  defp find_current(themes) do
    case Enum.find(themes, & &1.is_current) do
      nil -> nil
      theme -> schema_to_map(theme)
    end
  end

  defp publish_theme_broadcast(theme_map) do
    BotArmyRuntime.NATS.Publisher.publish("rpg.theme.current", theme_map)
  end

  defp publish_theme_event(theme_map) do
    BotArmyRpg.NATS.Publisher.publish("rpg.theme.changed", theme_map)
  end

  defp convert_to_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp convert_to_uuid(value), do: value

  defp schema_to_map(%Theme{} = theme) do
    %{
      "id" => Ecto.UUID.cast!(theme.id) |> to_string(),
      "tenant_id" => theme.tenant_id |> to_string(),
      "setting" => theme.setting,
      "tone" => theme.tone,
      "mechanic" => theme.mechanic,
      "vocabulary" => theme.vocabulary,
      "templates" => theme.templates,
      "npc_personas" => theme.npc_personas,
      "is_current" => theme.is_current,
      "changed_by" => theme.changed_by,
      "changed_at" => theme.updated_at |> NaiveDateTime.to_iso8601(),
      "created_at" => theme.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => theme.updated_at |> NaiveDateTime.to_iso8601()
    }
  end

  defp changeset_error_reason(%Ecto.Changeset{} = changeset) do
    {:validation_error, Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp changeset_error_reason(_), do: :database_error

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
