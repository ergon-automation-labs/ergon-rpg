defmodule BotArmyRpg.LoreNormalizer do
  @moduledoc """
  Maps inbound `rpg.lore.ingest` payloads into Lore Keeper facet upserts and drops.

  Unknown shapes return `{:error, :unknown_ingest_shape}`. Secrets must not appear in payloads.
  """

  @severity ~w(info notice warning critical)

  @doc """
  Returns `{:ok, %{upserts: [...], drops: [facet_id | ...]}}` or `{:error, reason}`.
  Upsert facets use string-keyed maps aligned with `lore_world_snapshot` facets.
  """
  def normalize_ingest(payload) when is_map(payload) do
    cond do
      Map.has_key?(payload, "facets") ->
        normalize_explicit(payload["facets"])

      Map.has_key?(payload, "ops_deploy") ->
        {:ok, from_ops_deploy(payload["ops_deploy"])}

      Map.has_key?(payload, "system_health") ->
        {:ok, from_system_health(payload["system_health"])}

      true ->
        {:error, :unknown_ingest_shape}
    end
  end

  def normalize_ingest(_), do: {:error, :unknown_ingest_shape}

  defp normalize_explicit(facets) when is_list(facets) do
    Enum.reduce_while(facets, {:ok, []}, fn facet, {:ok, acc} ->
      case normalize_explicit_facet(facet) do
        {:ok, u} -> {:cont, {:ok, [u | acc]}}
        {:error, r} -> {:halt, {:error, r}}
      end
    end)
    |> case do
      {:ok, upserts} -> {:ok, %{upserts: Enum.reverse(upserts), drops: []}}
      other -> other
    end
  end

  defp normalize_explicit(_), do: {:error, :invalid_facets}

  defp normalize_explicit_facet(facet) when is_map(facet) do
    id = facet["id"]
    severity = facet["severity"]

    with true <- is_binary(id) and id != "",
         true <- severity in @severity do
      inner =
        facet
        |> Map.take([
          "id",
          "severity",
          "summary",
          "count",
          "expires_at",
          "truth_refs",
          "attrs"
        ])
        |> Map.put_new("ttl_seconds", default_ttl_seconds(id))
        |> sanitize_optional_int("count")

      {:ok, %{"facet" => inner}}
    else
      _ -> {:error, :invalid_explicit_facet}
    end
  end

  defp normalize_explicit_facet(_), do: {:error, :invalid_explicit_facet}

  defp sanitize_optional_int(facet, key) do
    case facet[key] do
      nil ->
        facet

      n when is_integer(n) and n >= 0 ->
        Map.put(facet, key, n)

      _ ->
        Map.drop(facet, [key])
    end
  end

  defp from_ops_deploy(p) when is_map(p) do
    bot = Map.get(p, "bot", "unknown")
    node = Map.get(p, "node", "unknown")
    status = Map.get(p, "status")

    case status do
      "failed" ->
        attrs =
          Enum.reject([{"bot", bot}, {"node", node}], fn {_, v} -> v == "unknown" end)
          |> Map.new()

        facet = %{
          "facet" =>
            drop_nil(%{
              "id" => "deploy.failure",
              "severity" => "warning",
              "summary" => "Last ops deploy status=failed (#{bot} @ #{node})",
              "count" => 1,
              "ttl_seconds" => 86_400,
              "truth_refs" => [%{"kind" => "other", "ref" => "ops_deploy:#{bot}:#{node}"}],
              "attrs" => attrs
            })
        }

        %{upserts: [facet], drops: []}

      "success" ->
        %{upserts: [], drops: ["deploy.failure"]}

      _ ->
        %{upserts: [], drops: []}
    end
  end

  defp from_ops_deploy(_), do: %{upserts: [], drops: []}

  defp from_system_health(p) when is_map(p) do
    svc = Map.get(p, "service", "unknown")
    status = Map.get(p, "status")

    case status do
      s when s in ["unhealthy", "degraded"] ->
        severity = if s == "unhealthy", do: "critical", else: "warning"
        fid = facet_id_health(svc, s)

        facet = %{
          "facet" =>
            drop_nil(%{
              "id" => fid,
              "severity" => severity,
              "summary" => "Service #{svc} is #{s}",
              "ttl_seconds" => 3600,
              "truth_refs" => [%{"kind" => "other", "ref" => "system_health:#{svc}"}],
              "attrs" => %{"service" => svc, "status" => status}
            })
        }

        other =
          if s == "unhealthy",
            do: facet_id_health(svc, "degraded"),
            else: facet_id_health(svc, "unhealthy")

        %{upserts: [facet], drops: [other]}

      "healthy" ->
        %{
          upserts: [],
          drops: [facet_id_health(svc, "unhealthy"), facet_id_health(svc, "degraded")]
        }

      _ ->
        %{upserts: [], drops: []}
    end
  end

  defp from_system_health(_), do: %{upserts: [], drops: []}

  defp facet_id_health(service, kind)
       when is_binary(service) and kind in ["unhealthy", "degraded"] do
    slug =
      service
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "_")
      |> String.trim("_")

    "health.#{kind}.#{slug}"
  end

  defp drop_nil(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp default_ttl_seconds("poll." <> _), do: 86_400
  defp default_ttl_seconds("risk." <> _), do: 172_800
  defp default_ttl_seconds(_), do: 86_400
end
