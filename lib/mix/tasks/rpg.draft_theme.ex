defmodule Mix.Tasks.Rpg.DraftTheme do
  @shortdoc "Draft a theme preset from a TTRPG sourcebook PDF/text via NATS"

  @moduledoc """
  Drafts a theme preset by calling the `docs.theme.extract` NATS subject
  on `bot_army_internal_docs` and rendering the result as Elixir source
  under `priv/theme_drafts/`.

  ## Prerequisites

    * `bot_army_internal_docs` running (handler for `docs.theme.extract`).
    * `bot_army_llm` running (handler for `llm.prompt.submit`).
    * NATS reachable at `NATS_URL` (default `nats://localhost:4222`).
    * `pdftotext` on PATH if extracting from a PDF.

  ## Usage

      mix rpg.draft_theme NAME=verdant_hollow PDF=/path/to/sourcebook.pdf
      mix rpg.draft_theme NAME=verdant_hollow TEXT=/path/to/extracted.txt
      mix rpg.draft_theme NAME=verdant_hollow PDF=/path/to/book.pdf NATS_URL=nats://localhost:4222

  ## Arguments

    * `NAME` — required. Snake_case identifier for the new theme.
    * `PDF` — path to a PDF; passed to internal_docs as `pdf_path`.
    * `TEXT` — path to a plain text file (alternative to PDF). The file is
      read locally and sent inline as `text`.
    * `NATS_URL` — optional NATS server URL.
    * `TIMEOUT_MS` — optional total receive timeout (default 180000).
    * `BUDGET` — optional prompt budget in chars (default 12000).

  ## Output

  Writes `priv/theme_drafts/<name>.ex` plus `priv/theme_drafts/<name>.review.md`.
  Refuses to overwrite existing files. Copy the `.ex` into
  `lib/bot_army_rpg/themes/` once you're satisfied with the draft.

  ## Reviewing the draft

  The generated module is a valid `BotArmyRpg.Themes.Preset` and will be
  auto-discovered by the registry the moment it lands under `lib/`. Hold
  off on copying until you've:

    1. Reviewed `npc_personas` (LLMs hallucinate iconic items confidently).
    2. Sanity-checked vocabulary — TODO values mean the LLM punted.
    3. Confirmed nothing reads as a verbatim quote from the source. The
       extractor's prompts ask for paraphrase, but verify before publishing.
  """

  use Mix.Task

  @default_timeout_ms 180_000

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)

    name = opts[:name] || raise_missing!("NAME=<snake_case>")
    validate_name!(name)

    payload = build_payload(name, opts)

    Application.ensure_all_started(:gnat)

    case open_connection(opts) do
      {:ok, conn} ->
        try do
          do_request(conn, name, payload, opts)
        after
          Gnat.stop(conn)
        end

      {:error, reason} ->
        Mix.raise("Could not connect to NATS: #{inspect(reason)}")
    end
  end

  defp do_request(conn, name, payload, opts) do
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    Mix.shell().info("[rpg.draft_theme] Calling docs.theme.extract (timeout=#{timeout}ms)…")

    case Gnat.request(conn, "docs.theme.extract", Jason.encode!(payload),
           receive_timeout: timeout
         ) do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "theme" => theme} = response} ->
            write_outputs(name, theme, response, opts)

          {:ok, %{"ok" => false, "error" => err}} ->
            Mix.raise("Extractor returned error: #{inspect(err)}")

          {:ok, other} ->
            Mix.raise("Unexpected extractor response: #{inspect(other)}")

          {:error, reason} ->
            Mix.raise("Could not decode extractor response: #{inspect(reason)}")
        end

      {:error, :timeout} ->
        Mix.raise("docs.theme.extract timed out after #{timeout}ms")

      {:error, reason} ->
        Mix.raise("docs.theme.extract failed: #{inspect(reason)}")
    end
  end

  defp write_outputs(name, theme, response, opts) do
    File.mkdir_p!("priv/theme_drafts")
    module_path = "priv/theme_drafts/#{name}.ex"
    review_path = "priv/theme_drafts/#{name}.review.md"

    if File.exists?(module_path) do
      Mix.raise("Refusing to overwrite existing file: #{module_path}")
    end

    source =
      opts[:pdf_path] || opts[:text_path] || "inline text"

    warnings = Map.get(response, "warnings", [])
    errors = Map.get(response, "errors", [])

    rendered =
      BotArmyRpg.Themes.Renderer.render(name, theme,
        source: source,
        warnings: warnings
      )

    File.write!(module_path, rendered)
    File.write!(review_path, build_review(name, theme, response, source))

    Mix.shell().info("""

      Drafted theme: #{name}
        #{module_path}
        #{review_path}

    """)

    if errors != [] do
      Mix.shell().error("""
        ⚠ extractor surfaced #{length(errors)} error(s):
      #{Enum.map_join(errors, "\n", &"      - #{&1}")}
      """)
    end

    if warnings != [] do
      Mix.shell().info("""
        ⓘ extractor surfaced #{length(warnings)} warning(s):
      #{Enum.map_join(warnings, "\n", &"      - #{&1}")}
      """)
    end

    Mix.shell().info("""
      Next steps:
        $EDITOR #{review_path}
        mix format #{module_path}
        # then copy to lib/bot_army_rpg/themes/ when happy:
        cp #{module_path} lib/bot_army_rpg/themes/#{name}.ex
    """)
  end

  defp build_review(name, theme, response, source) do
    """
    # Theme draft: #{name}

    Generated by `mix rpg.draft_theme`. Treat this as an LLM first cut —
    edit aggressively before promoting to `lib/`.

    - Source: `#{source}`
    - Errors: #{length(Map.get(response, "errors", []))}
    - Warnings: #{length(Map.get(response, "warnings", []))}

    ## Setting fields

    - **setting**: #{theme["setting"]}
    - **tone**: #{theme["tone"]}
    - **mechanic**: #{theme["mechanic"]}

    ## Coverage

    | Section | Status |
    | --- | --- |
    | vocabulary | #{count_filled(theme["vocabulary"])} / 10 verbs filled (others = "TODO") |
    | npc_personas | #{map_size(theme["npc_personas"] || %{})} personas extracted |
    | templates | #{count_filled(theme["templates"])} / 5 templates filled |
    | rules.resolution | not extracted — declare manually if non-default |

    ## Review checklist

    - [ ] Skim `npc_personas` for hallucinated iconic items.
    - [ ] Replace any `"TODO"` strings with paraphrased setting language.
    - [ ] Decide on `rules.resolution` (or leave blank for d20 default).
    - [ ] Run `mix format priv/theme_drafts/#{name}.ex` before promoting.
    - [ ] Verbatim-overlap check against the source PDF (no quoted passages).
    """
  end

  defp count_filled(nil), do: 0

  defp count_filled(map) when is_map(map) do
    Enum.count(map, fn {_k, v} -> is_binary(v) and v != "" and v != "TODO" end)
  end

  defp build_payload(name, opts) do
    base = %{"theme_name" => name}

    base =
      cond do
        opts[:pdf_path] -> Map.put(base, "pdf_path", opts[:pdf_path])
        opts[:text_inline] -> Map.put(base, "text", opts[:text_inline])
        true -> Mix.raise("Either PDF=<path> or TEXT=<path> is required")
      end

    base =
      case opts[:budget] do
        nil -> base
        value -> Map.put(base, "prompt_budget_chars", value)
      end

    base
  end

  defp open_connection(opts) do
    url = opts[:nats_url] || System.get_env("NATS_URL") || "nats://localhost:4222"
    uri = URI.parse(url)
    host = uri.host || "localhost"
    port = uri.port || 4222

    Gnat.start_link(%{host: host, port: port}, name: nil)
  end

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        ["NAME", v] -> Keyword.put(acc, :name, v)
        ["PDF", v] -> Keyword.put(acc, :pdf_path, v)
        ["TEXT", v] -> put_text(acc, v)
        ["NATS_URL", v] -> Keyword.put(acc, :nats_url, v)
        ["TIMEOUT_MS", v] -> Keyword.put(acc, :timeout_ms, String.to_integer(v))
        ["BUDGET", v] -> Keyword.put(acc, :budget, String.to_integer(v))
        _ -> acc
      end
    end)
  end

  defp put_text(acc, path) do
    case File.read(path) do
      {:ok, content} ->
        acc
        |> Keyword.put(:text_path, path)
        |> Keyword.put(:text_inline, content)

      {:error, reason} ->
        Mix.raise("Could not read TEXT path #{path}: #{inspect(reason)}")
    end
  end

  defp raise_missing!(arg), do: Mix.raise("rpg.draft_theme requires #{arg}")

  defp validate_name!(name) do
    unless name =~ ~r/^[a-z][a-z0-9_]*$/ do
      Mix.raise("Invalid NAME #{inspect(name)} — must be snake_case starting with a letter.")
    end
  end
end
