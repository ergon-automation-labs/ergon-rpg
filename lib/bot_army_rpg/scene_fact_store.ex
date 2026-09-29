defmodule BotArmyRpg.SceneFactStore do
  @moduledoc "In-memory + Ecto store for scene facts and narrative state."
  use GenServer
  require Logger

  @server __MODULE__

  # A note says what it is in its own first word, so recognising one needs no
  # second field that could drift out of step with the content.
  @verification_mark "[verification]"

  # The machinery speaking is not a person in the scene.
  @machine_source "system"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def append(payload) when is_map(payload), do: GenServer.call(@server, {:append, payload})

  def list_for_session(tenant_id, session_id),
    do: GenServer.call(@server, {:list_for_session, tenant_id, session_id})

  @doc """
  The newest turns of this identity's *other* windows, newest first.

  The window's own turns are excluded, because the caller already has them: what
  this answers is what came before the window that is open now.

  `:story_only` leaves out the notes the machinery wrote (see `story?/1`), and it
  leaves them out **before** `:limit` is applied — a caller asking for the newest
  ten turns gets ten turns, not ten rows of which some turned out to be notes.
  """
  def list_recent_for_tenant(tenant_id, opts \\ []),
    do: GenServer.call(@server, {:list_recent_for_tenant, tenant_id, opts})

  @doc """
  Is this fact *story* — something that happened in a window — rather than a note
  the machinery wrote?

  Two facts are not story. One whose `source` is `"system"`: the machinery is not
  someone in the scene, and a thing it notes is not a thing that happened to her.
  One whose content declares itself a check in its own first word,
  `[verification]` — compared after leading whitespace and without case, so a note
  does not become story by being indented or capitalised.

  The convention exists because a feature is sometimes proved by writing a fact
  into a real window on purpose, and that note then sits in the window's history.
  `select_recent/3` is where it is acted on; the *policy* — that the carry takes
  turns and not notes — is stated by the caller that asks for `:story_only`.
  """
  def story?(%{"source" => @machine_source}), do: false
  def story?(%{"content" => content}) when is_binary(content), do: not test_note?(content)
  def story?(_fact), do: true

  @doc """
  The selection `list_recent_for_tenant/2` answers, with the GenServer taken out.

  Pure so that the *order of the steps* can be stated and tested rather than
  reasoned about: the note filter runs before the sort and the limit.
  """
  def select_recent(facts, tenant_id, opts) when is_list(facts) do
    exclude = Keyword.get(opts, :exclude_session_id)
    user_id = Keyword.get(opts, :user_id)
    limit = Keyword.get(opts, :limit, 10)

    facts
    |> Enum.filter(&(&1["tenant_id"] == tenant_id and &1["user_id"] == user_id))
    |> reject_session(exclude)
    |> reject_notes(Keyword.get(opts, :story_only, false))
    |> Enum.sort_by(& &1["created_at"], :desc)
    |> Enum.take(limit)
  end

  def clear, do: GenServer.call(@server, :clear)

  @impl true
  def init(_opts) do
    Logger.info("[SceneFactStore] Starting")

    state =
      try do
        facts = BotArmyRpg.Repo.all(BotArmyRpg.Schemas.SceneFact)

        Enum.reduce(facts, %{}, fn fact, acc ->
          Map.put(acc, fact.id |> to_string(), schema_to_map(fact))
        end)
      rescue
        _ ->
          Logger.warning("[SceneFactStore] Database unavailable, starting empty")
          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:append, payload}, _from, state) do
    fact_id = Ecto.UUID.generate()
    tenant_id = payload["tenant_id"] || BotArmyLibraryRuntime.Tenant.default_tenant_id()
    user_id = Map.get(payload, "user_id")

    changeset =
      BotArmyRpg.Schemas.SceneFact.changeset(
        %BotArmyRpg.Schemas.SceneFact{id: fact_id},
        %{
          "tenant_id" => convert_to_uuid(tenant_id),
          "user_id" => if(user_id, do: convert_to_uuid(user_id), else: nil),
          "session_id" => convert_to_uuid(payload["session_id"]),
          "content" => payload["content"],
          "category" => Map.get(payload, "category", "observation"),
          "source" => Map.get(payload, "source", "gm")
        }
      )

    case BotArmyRpg.Repo.insert(changeset) do
      {:ok, db_fact} ->
        fact = schema_to_map(db_fact)
        new_state = Map.put(state, fact_id, fact)
        Logger.info("[SceneFactStore] Appended fact: #{fact_id}")
        {:reply, {:ok, fact}, new_state}

      {:error, changeset} ->
        Logger.error("[SceneFactStore] Failed to append fact: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset_error_reason(changeset)}, state}
    end
  end

  @impl true
  def handle_call({:list_for_session, tenant_id, session_id}, _from, state) do
    facts =
      state
      |> Map.values()
      |> Enum.filter(&(&1["tenant_id"] == tenant_id and &1["session_id"] == session_id))
      |> Enum.sort_by(& &1["created_at"])

    {:reply, {:ok, facts}, state}
  end

  @impl true
  def handle_call({:list_recent_for_tenant, tenant_id, opts}, _from, state) do
    {:reply, {:ok, select_recent(Map.values(state), tenant_id, opts)}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    BotArmyRpg.Repo.delete_all(BotArmyRpg.Schemas.SceneFact)
    {:reply, :ok, %{}}
  end

  # Only a named window is excluded: an unnamed one must not drop facts that carry
  # no session id at all.
  defp reject_session(facts, exclude) when is_binary(exclude) and exclude != "",
    do: Enum.reject(facts, &(&1["session_id"] == exclude))

  defp reject_session(facts, _exclude), do: facts

  defp reject_notes(facts, true), do: Enum.filter(facts, &story?/1)
  defp reject_notes(facts, _otherwise), do: facts

  defp test_note?(content) do
    content
    |> String.trim_leading()
    |> String.downcase()
    |> String.starts_with?(@verification_mark)
  end

  defp convert_to_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> generate_uuid_from_string(value)
    end
  end

  defp convert_to_uuid(value), do: value

  defp generate_uuid_from_string(string) when is_binary(string) do
    hash = :crypto.hash(:sha256, string)
    <<uuid_int::128>> = binary_part(hash, 0, 16)
    <<uuid_int::128>> |> Ecto.UUID.cast() |> elem(1)
  end

  defp schema_to_map(%BotArmyRpg.Schemas.SceneFact{} = fact) do
    %{
      "id" => Ecto.UUID.cast!(fact.id) |> to_string(),
      "tenant_id" => fact.tenant_id |> to_string(),
      "user_id" => if(fact.user_id, do: fact.user_id |> to_string(), else: nil),
      "session_id" => fact.session_id |> to_string(),
      "content" => fact.content,
      "category" => fact.category,
      "source" => fact.source,
      "created_at" => fact.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => fact.updated_at |> NaiveDateTime.to_iso8601()
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
