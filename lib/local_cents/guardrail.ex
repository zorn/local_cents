defmodule LocalCents.Guardrail do
  @moduledoc """
  The pure half of the guardrail check that flags a change touching our
  static-analysis surfaces so an admin reviews it before it merges.

  Credo and Sobelow enforce our coding and security standards in CI, and both can
  be silenced locally — a `credo:disable` comment, a Sobelow skip comment, an edit
  to `.credo.exs` or `.sobelow-conf`, or an edit to a workflow file. None of those
  is wrong on its own; each is *sensitive*, and the point of the check is to make
  the change a conscious decision rather than let it land unseen. This module reads
  a `git diff` and the list of changed paths and reports every such move.

  The expected flow: a PR that touches one of these surfaces fails this check on
  purpose, an admin merges it knowing the red mark is the deliberate "I reviewed
  this" sign-off, and a later PR that touches none of them passes clean. The check
  runs on pull requests only, so a merge to `main` is never held by it.

  Nothing here touches git, a disk, or a network: `Mix.Tasks.Guardrail.Review`
  gathers the diff and the path list and hands them in as strings.

  Two rules keep the scan honest against false positives:

    * A skip only counts when the added line, once its diff marker is stripped and
      the remainder trimmed, *starts* with the directive. A real skip is always a
      standalone comment line, so a mention inside a string literal or prose (this
      module's own tests carry the patterns as fixture data) never trips it.
    * Skips are read only from `.ex`/`.exs` files, the only place a Credo or
      Sobelow directive means anything.

  A skip counts whenever it is on an *added* line, so editing an existing skip —
  which the diff shows as a removed line and an added one — trips the check on its
  new side. That is deliberate: an edit can broaden a suppression or point it at a
  different check, so it gets the same look as a brand-new skip. Only removing a
  skip, or leaving one untouched in a file edited elsewhere, stays silent.
  """

  defmodule Violation do
    @moduledoc """
    One change to a guardrail surface, found in a diff and located well enough to
    point a reviewer at it.

    `line` is the new-side line number for a skip, and `nil` for a whole-file
    change (a config or workflow edit) where the path is the unit of review.
    `detail` carries the offending directive text for a skip, and is `nil` for a
    whole-file change.
    """

    @type kind() :: :credo_skip | :sobelow_skip | :config | :workflow

    @type t() :: %__MODULE__{
            kind: kind(),
            file: String.t(),
            line: pos_integer() | nil,
            detail: String.t() | nil
          }

    @enforce_keys [:kind, :file]
    defstruct [:kind, :file, :line, :detail]
  end

  # `\A` anchors each pattern to the start of the trimmed line — see the moduledoc
  # for why a directive only counts as its own comment line. The Credo pattern
  # matches every `disable-for-*` form (this-file, next-line, previous-line,
  # lines:N) rather than an enumerated pair, so a form we forget still trips.
  #
  # The attribute for the Sobelow directive is deliberately not named
  # `@sobelow_skip`: Sobelow reads any `@sobelow_skip` module attribute as a real
  # skip directive and crashes trying to parse this regex as its argument list.
  @credo_directive ~r/\A#\s*credo:disable-for-\S/
  @sobelow_directive ~r/\A#\s*sobelow_skip\b/

  # Config filenames matched by basename, not path: Credo reads a `.credo.exs`
  # from any config dir (e.g. `config/.credo.exs`), so gating only the root copy
  # would leave a subdir copy as an escape hatch.
  @config_filenames [".credo.exs", ".sobelow-conf"]

  # Matches both extensions GitHub Actions honors: guarding only `.yaml` would
  # leave renaming the Credo step into a new `.yml` workflow as an escape hatch.
  @workflow_file ~r{\A\.github/workflows/[^/]+\.ya?ml\z}

  @doc """
  Every change to a guardrail surface in `diff` (a `git diff --unified=0` body) and
  `changed_files` (the `git diff --name-only` list), most useful first: the
  added skips, then the config and workflow edits.
  """
  @spec review(diff :: String.t(), changed_files :: [String.t()]) :: [Violation.t()]
  def review(diff, changed_files) do
    added_skips(diff) ++ guarded_file_changes(changed_files)
  end

  @doc """
  Renders `violations` as a reviewer-facing message naming each offending file
  (and line, for a skip), or `nil` when the list is empty.
  """
  @spec format(violations :: [Violation.t()]) :: String.t() | nil
  def format([]), do: nil

  def format(violations) do
    """
    This change modifies our static-analysis guardrails. Each item below needs an \
    admin to review and approve the merge:

    #{Enum.map_join(violations, "\n", &("  " <> describe(&1)))}
    """
  end

  defp describe(%Violation{kind: :credo_skip, file: file, line: line, detail: detail}),
    do: "#{file}:#{line} adds a Credo skip — #{detail}"

  defp describe(%Violation{kind: :sobelow_skip, file: file, line: line, detail: detail}),
    do: "#{file}:#{line} adds a Sobelow skip — #{detail}"

  defp describe(%Violation{kind: :config, file: file}),
    do: "#{file} is a guardrail config file and was changed"

  defp describe(%Violation{kind: :workflow, file: file}),
    do: "#{file} is a CI workflow file and was changed"

  defp added_skips(diff) do
    diff
    |> added_lines()
    |> Enum.flat_map(&skip_violation/1)
  end

  defp skip_violation(%{file: file, line: line, text: text}) do
    trimmed = String.trim_leading(text)

    cond do
      not elixir_source?(file) -> []
      Regex.match?(@credo_directive, trimmed) -> [skip(:credo_skip, file, line, trimmed)]
      Regex.match?(@sobelow_directive, trimmed) -> [skip(:sobelow_skip, file, line, trimmed)]
      true -> []
    end
  end

  defp skip(kind, file, line, trimmed),
    do: %Violation{kind: kind, file: file, line: line, detail: trimmed}

  defp guarded_file_changes(changed_files) do
    Enum.flat_map(changed_files, fn file ->
      cond do
        Path.basename(file) in @config_filenames -> [%Violation{kind: :config, file: file}]
        Regex.match?(@workflow_file, file) -> [%Violation{kind: :workflow, file: file}]
        true -> []
      end
    end)
  end

  defp elixir_source?(file), do: String.ends_with?(file, [".ex", ".exs"])

  # Reduces the diff to its added lines as `%{file, line, text}`. The line is the
  # new-side number, read from each hunk header's `+start` and advanced by every
  # added or context line; a removed line never advances it. So the number a skip
  # reports is where it lands in the file after the change, whatever the hunk's
  # context width.
  defp added_lines(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce({nil, nil, []}, &scan_line/2)
    |> elem(2)
    |> Enum.reverse()
  end

  # Only the two real new-side headers git emits with default prefixes reset the
  # file. A looser `"+++ "` match would also catch an added source line whose
  # content is `++ …`, which prints as `+++ …` in the diff — that line must fall
  # through to the `"+"` clause and be read as content, not a header.
  defp scan_line("+++ b/" <> path, {_file, line, acc}), do: {path, line, acc}
  defp scan_line("+++ /dev/null" <> _, {_file, line, acc}), do: {nil, line, acc}
  defp scan_line("--- " <> _, {file, line, acc}), do: {file, line, acc}

  defp scan_line("@@" <> _ = header, {file, _line, acc}),
    do: {file, hunk_start(header), acc}

  defp scan_line("+" <> text, {file, line, acc}) when is_integer(line),
    do: {file, line + 1, [%{file: file, line: line, text: text} | acc]}

  defp scan_line("-" <> _, {file, line, acc}), do: {file, line, acc}
  defp scan_line(" " <> _, {file, line, acc}) when is_integer(line), do: {file, line + 1, acc}
  defp scan_line(_other, {file, line, acc}), do: {file, line, acc}

  defp hunk_start(header) do
    case Regex.run(~r/\+(\d+)/, header) do
      [_, start] -> String.to_integer(start)
      nil -> nil
    end
  end
end
