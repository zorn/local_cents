defmodule Mix.Tasks.Docs.Mermaid do
  @shortdoc "Checks that every Mermaid diagram in our Markdown parses"

  @moduledoc """
  Parses every ```` ```mermaid ```` block in the repo's Markdown and fails if any
  of them is invalid.

  Nothing else in the build reads these blocks. ExDoc emits a Mermaid fence as
  `<pre><code class="mermaid">` and leaves the parsing to the reader's browser, so
  a broken diagram sails through `mix docs --warnings-as-errors` and lands on the
  published page as an error bomb. This task closes that gap by running the blocks
  through the real `mermaid.parse()`, at the version the docs actually load.

  ## How it runs

  `mermaid.parse()` needs a DOM, so the check drives a headless Chrome over a
  generated page — see `LocalCents.Docs.Mermaid` for the page and
  `LocalCents.Docs.Mermaid.Runner` for the browser. Chrome is used rather than
  Node + jsdom because GitHub's runners already ship it and this project keeps npm
  out of the tree. Mermaid itself is fetched once from the same CDN URL the docs
  load and cached under `_build/mermaid/`.

      $ mix docs.mermaid                    # every Markdown file git tracks
      $ mix docs.mermaid docs/adr/*.md      # just these

  ## Options

    * `--strict` — fail instead of skipping when the check *cannot* run: no
      browser was found, or Mermaid could not be fetched. CI passes this;
      `mix precommit` does not, so a contributor without Chrome or without a
      network connection still gets a green local run rather than a wall they
      cannot climb.

  Set `CHROME_BIN` to point at a specific browser binary if the one you want is
  not in the search list.
  """

  use Mix.Task
  use Boundary, classify_to: LocalCents

  alias LocalCents.Docs.Mermaid
  alias LocalCents.Docs.Mermaid.Runner

  # `app.config` compiles and loads config without starting the app — this task
  # needs `LocalCents.Docs.Mermaid` on the code path, not a running endpoint.
  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, paths} = OptionParser.parse!(argv, strict: [strict: :boolean])
    strict? = Keyword.get(opts, :strict, false)

    case paths |> markdown_files() |> Enum.flat_map(&extract/1) do
      [] -> Mix.shell().info("No Mermaid diagrams found.")
      blocks -> check(blocks, strict?)
    end
  end

  defp check(blocks, strict?) do
    case Runner.run(blocks) do
      {:ok, results} ->
        report(blocks, results)

      {:skip, reason} when strict? ->
        Mix.raise("The Mermaid check could not run: #{reason}.")

      {:skip, reason} ->
        Mix.shell().info("Skipping the Mermaid check — #{reason}.")

      # Unlike a skip, this means the browser ran and left the diagrams
      # unchecked anyway — exactly what this task exists to catch.
      {:error, reason} ->
        Mix.raise("The Mermaid check could not be completed: #{reason}.")
    end
  end

  defp extract(path), do: Mermaid.extract_blocks(path, File.read!(path))

  # Defaults to what git tracks, which keeps the walk out of `deps/`, `_build/`,
  # and the Rust `target/` directories without maintaining an ignore list that
  # would drift from `.gitignore`. `CLAUDE.md` is a symlink to `AGENTS.md`, so
  # paths are deduped by their resolved target to avoid checking a file twice.
  defp markdown_files([]) do
    case tracked_markdown_files() do
      {output, 0} -> output |> String.split(<<0>>, trim: true) |> dedupe_links()
      _ -> markdown_files(["*.md", "docs/**/*.md"])
    end
  end

  defp markdown_files(patterns) do
    patterns |> Enum.flat_map(&Path.wildcard/1) |> dedupe_links()
  end

  # `System.cmd/3` raises rather than returning a status when the binary is
  # absent, so an un-installed git has to fall back the same way a non-git
  # checkout does.
  defp tracked_markdown_files do
    System.cmd("git", ["ls-files", "-z", "--", "*.md"], env: [], stderr_to_stdout: true)
  rescue
    ErlangError -> {"", 1}
  end

  defp dedupe_links(paths) do
    Enum.uniq_by(paths, fn path ->
      case File.read_link(path) do
        {:ok, target} -> target |> Path.expand(Path.dirname(path)) |> Path.relative_to_cwd()
        {:error, _reason} -> path
      end
    end)
  end

  defp report(blocks, results) do
    failures =
      blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, id} ->
        case Map.fetch(results, id) do
          {:ok, nil} -> []
          {:ok, error} -> [Mermaid.format_failure(block, error)]
          :error -> [Mermaid.format_failure(block, "the browser reported no result")]
        end
      end)

    if failures == [] do
      Mix.shell().info("All #{length(blocks)} Mermaid diagram(s) parsed.")
    else
      Mix.raise("""
      #{length(failures)} of #{length(blocks)} Mermaid diagram(s) failed to parse \
      under Mermaid #{Mermaid.version()}:

      #{Enum.map_join(failures, "\n", &("  " <> &1))}

      Note the pinned version: syntax the Mermaid playground accepts (it tracks \
      latest) can fail here.\
      """)
    end
  end
end
