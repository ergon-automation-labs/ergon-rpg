defmodule BotArmyRpg.IdentityBindingStore do
  @moduledoc "In-memory store mapping user identities to RPG characters."
  use GenServer
  require Logger

  @server __MODULE__
  @binding_keys ~w(surface client_id channel_id guild_id theme_id connection_id)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  def bind(tenant_id, attrs, user_id) when is_map(attrs) do
    GenServer.call(@server, {:bind, tenant_id, attrs, user_id})
  end

  def resolve(tenant_id, attrs) when is_map(attrs) do
    GenServer.call(@server, {:resolve, tenant_id, attrs})
  end

  def resolve_binding(tenant_id, attrs) when is_map(attrs) do
    GenServer.call(@server, {:resolve_binding, tenant_id, attrs})
  end

  def set_identity_sync(tenant_id, attrs, identity_sync) when is_map(attrs) do
    GenServer.call(@server, {:set_identity_sync, tenant_id, attrs, identity_sync})
  end

  @impl true
  def init(_opts) do
    Logger.info("[IdentityBindingStore] Starting")
    {:ok, load_seed_bindings()}
  end

  @impl true
  def handle_call({:bind, tenant_id, attrs, user_id}, _from, state) do
    key = binding_key(tenant_id, attrs)
    normalized_user_id = normalize_user_id(user_id)
    existing = Map.get(state, key, %{})

    binding =
      existing
      |> Map.put("user_id", normalized_user_id)
      |> Map.put_new("identity_sync", nil)

    new_state = Map.put(state, key, binding)
    {:reply, {:ok, normalized_user_id}, new_state}
  end

  @impl true
  def handle_call({:resolve, tenant_id, attrs}, _from, state) do
    user_id =
      state
      |> Map.get(binding_key(tenant_id, attrs))
      |> case do
        %{"user_id" => resolved_user_id} -> resolved_user_id
        _ -> nil
      end

    {:reply, user_id, state}
  end

  @impl true
  def handle_call({:resolve_binding, tenant_id, attrs}, _from, state) do
    binding = Map.get(state, binding_key(tenant_id, attrs))
    {:reply, binding, state}
  end

  @impl true
  def handle_call({:set_identity_sync, tenant_id, attrs, identity_sync}, _from, state) do
    key = binding_key(tenant_id, attrs)

    new_state =
      case Map.get(state, key) do
        %{"user_id" => _} = binding ->
          Map.put(state, key, Map.put(binding, "identity_sync", identity_sync))

        _ ->
          state
      end

    {:reply, :ok, new_state}
  end

  defp binding_key(tenant_id, attrs) do
    parts =
      attrs
      |> Map.take(@binding_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.sort()

    {tenant_id, parts}
  end

  defp load_seed_bindings do
    case System.get_env("RPG_IDENTITY_BINDINGS_JSON") do
      nil ->
        %{}

      json ->
        case Jason.decode(json) do
          {:ok, bindings} when is_list(bindings) ->
            Enum.reduce(bindings, %{}, fn entry, acc ->
              tenant_id = Map.get(entry, "tenant_id") || BotArmyLibraryRuntime.Tenant.default_tenant_id()
              user_id = Map.get(entry, "user_id")

              if is_binary(user_id) do
                key = binding_key(tenant_id, entry)

                Map.put(acc, key, %{
                  "user_id" => normalize_user_id(user_id),
                  "identity_sync" => nil
                })
              else
                acc
              end
            end)

          {:ok, _} ->
            Logger.warning(
              "[IdentityBindingStore] RPG_IDENTITY_BINDINGS_JSON must be a JSON array"
            )

            %{}

          {:error, reason} ->
            Logger.warning(
              "[IdentityBindingStore] Failed parsing RPG_IDENTITY_BINDINGS_JSON: #{inspect(reason)}"
            )

            %{}
        end
    end
  end

  defp normalize_user_id(user_id) when is_binary(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        uuid

      :error ->
        hash = :crypto.hash(:sha256, user_id)
        <<uuid_int::128>> = binary_part(hash, 0, 16)
        <<uuid_int::128>> |> Ecto.UUID.cast() |> elem(1)
    end
  end

  defp normalize_user_id(user_id), do: user_id
end
