defmodule Mix.Tasks.Mermaid.Check do
  @shortdoc "Checks that every Mermaid diagram in our Markdown parses"

  @moduledoc """
  Parses every ```` ```mermaid ```` block we publish and fails if any of them is
  invalid — the gap `mix docs --warnings-as-errors` leaves open, since ExDoc never
  reads a diagram. Background and the syntax traps that have caught us out:
  [Mermaid Diagrams](mermaid-diagrams.html).

      $ mix mermaid.check                    # every tracked `.md` and `lib/*.ex`
      $ mix mermaid.check docs/adr/*.md      # just these

  With no arguments the scope is what git tracks, Markdown *and* `lib/*.ex` — a
  fence inside a `@moduledoc` reaches the published page the same way one in a
  guide does. Test files are excluded so a fixture may hold a broken diagram.

  `mermaid.parse()` needs a DOM, so the check drives a headless Chrome over a
  generated page: `LocalCents.Docs.Mermaid` builds the page,
  `LocalCents.Docs.Mermaid.Runner` runs it. Chrome rather than Node + jsdom
  because GitHub's runners already ship it and this project keeps npm out of the
  tree ([`CODING_STANDARDS.md`](https://github.com/zorn/local_cents/blob/main/CODING_STANDARDS.md)).

  ## Options

    * `--strict` — fail instead of skipping when the check cannot produce a
      verdict. CI passes this; `mix precommit` does not, so a missing browser or
      a missing network connection is a notice locally and a failure in CI.

  Set `CHROME_BIN` to point at a specific browser binary if the one you want is
  not in the search list.
  """

  # Named `mermaid.check` rather than `docs.mermaid`, which would read better next
  # to `mix docs`: a Mix task's module name *is* its task name, so nesting under
  # `docs` would put this module inside `Mix.Tasks.Docs`, a namespace ExDoc owns.
  # Sharing it works until ExDoc ships a task of the same name, and the failure
  # then is a module collision rather than anything easy to read.
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

    case paths |> source_files() |> Enum.flat_map(&extract/1) do
      [] -> Mix.shell().info("No Mermaid diagrams found.")
      blocks -> check(blocks, strict?)
    end
  end

  defp check(blocks, strict?) do
    case Runner.run(blocks) do
      {:ok, results} -> report(blocks, Mermaid.failures(blocks, results))
      {:skip, reason} when strict? -> Mix.raise("The Mermaid check could not run: #{reason}.")
      {:skip, reason} -> Mix.shell().info("Skipping the Mermaid check — #{reason}.")
    end
  end

  defp extract(path), do: Mermaid.extract_blocks(path, File.read!(path))

  # Defaults to what git tracks, which keeps the walk out of `deps/`, `_build/`,
  # and the Rust `target/` directories without maintaining an ignore list that
  # would drift from `.gitignore`. `CLAUDE.md` is a symlink to `AGENTS.md`, so
  # paths are deduped by their resolved target to avoid checking a file twice.
  defp source_files([]) do
    case tracked_files() do
      {output, 0} -> output |> String.split(<<0>>, trim: true) |> dedupe_links()
      _ -> source_files(["*.md", "docs/**/*.md", "lib/**/*.ex"])
    end
  end

  defp source_files(patterns) do
    patterns |> Enum.flat_map(&Path.wildcard/1) |> dedupe_links()
  end

  # `lib/*.ex` is in scope alongside the Markdown because ExDoc injects its
  # Mermaid script into *every* generated page, module pages included — a fence in
  # a `@moduledoc` renders in the browser exactly like one in a guide. Test files
  # are left out: they are never published, and a fixture is allowed to hold a
  # deliberately broken diagram.
  #
  # `System.cmd/3` raises rather than returning a status when the binary is
  # absent, so an un-installed git has to fall back the same way a non-git
  # checkout does.
  defp tracked_files do
    System.cmd("git", ["ls-files", "-z", "--", "*.md", "lib/*.ex"],
      env: [],
      stderr_to_stdout: true
    )
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

  defp report(blocks, failures) do
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
