defmodule LocalCents.Guardrail do
  @moduledoc """
  The pure half of the guardrail check that stops a change from quietly weakening
  our static-analysis teeth.

  Credo and Sobelow enforce our coding and security standards in CI, and both can
  be silenced locally — a `credo:disable` comment, a Sobelow skip comment, an edit
  to `.credo.exs` or `.sobelow-conf`, or an edit to a workflow file that deletes
  the step outright. This module reads a `git diff` and the list of changed paths
  and reports every one of those moves, so the check that wraps it
  (`mix guardrail.review`) can force a conscious admin override rather than let the
  suppression land unseen.

  Nothing here touches git, a disk, or a network: `Mix.Tasks.Guardrail.Review`
  gathers the diff and the path list and hands them in as strings.

  Two rules keep the scan honest against false positives:

    * A skip only counts when the added line, once its diff marker is stripped and
      the remainder trimmed, *starts* with the directive. A real skip is always a
      standalone comment line, so a mention inside a string literal or prose (this
      module's own tests carry the patterns as fixture data) never trips it.
    * Skips are read only from `.ex`/`.exs` files, the only place a Credo or
      Sobelow directive means anything.
  """

  defmodule Violation do
    @moduledoc """
    One guardrail-weakening change found in a diff, located well enough to point a
    reviewer at it.

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
  # for why a directive only counts as its own comment line. The attribute for the
  # Sobelow directive is deliberately not named `@sobelow_skip`: Sobelow reads any
  # `@sobelow_skip` module attribute as a real skip directive and crashes trying
  # to parse this regex as its argument list.
  @credo_directive ~r/\A#\s*credo:disable-for-(?:this-file|next-line)\b/
  @sobelow_directive ~r/\A#\s*sobelow_skip\b/

  # The two global tool configs. Any edit to either can loosen a rule for the
  # whole tree, so a touch is enough to warrant review.
  @config_files [".credo.exs", ".sobelow-conf"]

  # Matches both extensions GitHub Actions honors: guarding only `.yaml` would
  # leave renaming the Credo step into a new `.yml` workflow as an escape hatch.
  @workflow_file ~r{\A\.github/workflows/[^/]+\.ya?ml\z}

  @doc """
  Every guardrail-weakening change in `diff` (a `git diff --unified=0` body) and
  `changed_files` (the `git diff --name-only` list), most useful first: the
  net-new skips, then the config and workflow edits.
  """
  @spec review(String.t(), [String.t()]) :: [Violation.t()]
  def review(diff, changed_files) do
    added_skips(diff) ++ guarded_file_changes(changed_files)
  end

  @doc """
  Renders `violations` as a reviewer-facing message naming each offending file
  (and line, for a skip), or `nil` when the list is empty.
  """
  @spec format([Violation.t()]) :: String.t() | nil
  def format([]), do: nil

  def format(violations) do
    """
    This change weakens our static-analysis guardrails. Each item below needs a \
    deliberate admin override to merge:

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
        file in @config_files -> [%Violation{kind: :config, file: file}]
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

  defp scan_line("+++ b/" <> path, {_file, line, acc}), do: {path, line, acc}
  defp scan_line("+++ " <> path, {_file, line, acc}), do: {path, line, acc}
  defp scan_line("---" <> _, {file, line, acc}), do: {file, line, acc}

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
