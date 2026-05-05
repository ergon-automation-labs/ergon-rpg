defmodule BotArmyRpg.LoreKeeper do
  @moduledoc """
  In-memory per-tenant lore facets and rollups for the Resistance Chronicle Lore Keeper.

  State is ephemeral (restart clears). Automated decisions must **not** use this module.
  """
  use GenServer

  alias BotArmyRpg.LoreNormalizer

  @schema_version "1.0"
  @max_facets 64

  @severity_rank %{"critical" => 4, "warning" => 3, "notice" => 2, "info" => 1}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `{:ok, world_snapshot}` with string-keyed maps (JSON-compatible).
  """
  def snapshot(tenant_id) when is_binary(tenant_id) do
    GenServer.call(__MODULE__, {:snapshot, tenant_id})
  end

  def snapshot(_), do: {:error, :invalid_tenant}

  @doc """
  Ingest lore signals; merges facet upserts and applies drops derived from payloads.
  """
  def ingest(tenant_id, payload) when is_binary(tenant_id) and is_map(payload) do
    GenServer.call(__MODULE__, {:ingest, tenant_id, payload})
  end

  def ingest(_, _), do: {:error, :invalid_tenant}

  @doc """
  Drops all lore facets for a tenant (typically tests). Does not belong on security-sensitive paths.
  """
  def forget_tenant(tenant_id) when is_binary(tenant_id) do
    GenServer.call(__MODULE__, {:forget_tenant, tenant_id})
  end

  def forget_tenant(_), do: {:error, :invalid_tenant}

  @impl true
  def init(_opts) do
    {:ok, %{tenants: %{}}}
  end

  @impl true
  def handle_call({:snapshot, tenant_id}, _from, state) do
    {:reply, {:ok, build_world_snapshot(state, tenant_id)}, state}
  end

  @impl true
  def handle_call({:ingest, tenant_id, payload}, _from, state) do
    case LoreNormalizer.normalize_ingest(payload) do
      {:ok, ops} ->
        state2 =
          state
          |> apply_drops(tenant_id, ops.drops)
          |> apply_upserts(tenant_id, ops.upserts)

        {:reply,
         {:ok,
          %{
            "ingested_facets" => length(ops.upserts),
            "dropped_facets" => length(ops.drops)
          }}, state2}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:forget_tenant, tenant_id}, _from, state) do
    tenants = Map.delete(state.tenants, tenant_id)
    {:reply, :ok, %{state | tenants: tenants}}
  end

  defp apply_drops(state, tenant_id, drop_ids) do
    m = Map.get(state.tenants, tenant_id, %{})

    m2 =
      Enum.reduce(drop_ids, m, fn id, acc ->
        Map.delete(acc, id)
      end)

    tenants_root =
      if map_size(m2) == 0 do
        Map.delete(state.tenants, tenant_id)
      else
        Map.put(state.tenants, tenant_id, m2)
      end

    %{state | tenants: tenants_root}
  end

  defp apply_upserts(state, tenant_id, upsert_wrappers) do
    m = Map.get(state.tenants, tenant_id, %{})

    m2 =
      Enum.reduce(upsert_wrappers, m, fn %{"facet" => inner}, acc ->
        id = inner["id"]
        now_dt = utc_now_trunc()
        now_iso = format_dt(now_dt)

        expires_iso =
          case inner["expires_at"] do
            s when is_binary(s) and s != "" ->
              s

            _ ->
              ttl =
                case inner["ttl_seconds"] do
                  n when is_integer(n) and n > 0 and n <= 86_400 * 365 -> n
                  _ -> 86_400
                end

              now_dt |> DateTime.add(ttl, :second) |> format_dt()
          end

        merged =
          inner
          |> Map.drop(["ttl_seconds"])
          |> Map.put("last_seen_at", now_iso)
          |> Map.put("expires_at", expires_iso)
          |> then(fn facet ->
            case Map.fetch(acc, id) do
              {:ok, %{"first_seen_at" => fs}} ->
                Map.put(facet, "first_seen_at", fs)

              _ ->
                Map.put(facet, "first_seen_at", now_iso)
            end
          end)

        Map.put(acc, id, merged)
      end)

    %{state | tenants: Map.put(state.tenants, tenant_id, m2)}
  end

  defp build_world_snapshot(state, tenant_id) do
    now_dt = utc_now_trunc()
    facets_base = Map.get(state.tenants, tenant_id, %{})

    facets =
      facets_base
      |> Map.values()
      |> Enum.filter(&facet_live?(&1, now_dt))
      |> Enum.sort_by(
        fn f ->
          {-Map.get(@severity_rank, f["severity"], 0), Map.get(f, "last_seen_at", "")}
        end,
        :asc
      )
      |> Enum.take(@max_facets)

    rollups = %{
      "open_critical_facets" => Enum.count(facets, fn f -> f["severity"] == "critical" end),
      "open_warning_facets" => Enum.count(facets, fn f -> f["severity"] == "warning" end)
    }

    %{
      "schema_version" => @schema_version,
      "generated_at" => format_dt(now_dt),
      "tenant_id" => tenant_id,
      "facets" => facets,
      "rollups" => rollups
    }
  end

  defp facet_live?(facet, now_dt) do
    case parse_dt(facet["expires_at"]) do
      {:ok, exp} -> DateTime.compare(exp, now_dt) == :gt
      _ -> false
    end
  end

  defp utc_now_trunc do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse_dt(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, :missing_offset} ->
        case DateTime.from_iso8601(iso <> "Z") do
          {:ok, dt, _o} -> {:ok, dt}
          err -> err
        end

      err ->
        err
    end
  end

  defp parse_dt(_), do: {:error, :invalid_date}
end
