# A project-local Credo check, loaded via the `requires:` key in `.credo.exs` so
# it stays out of the compiled application — Credo is a dev/test-only dependency
# and this module `use`s it, so it must never be part of a release build.
#
# Independent reimplementation of the idea behind
# `ExSlop.Check.Refactor.CaseTrueFalse` (MIT, © 2026 Danila Poyarkov). We vendor
# this single rule rather than take on the whole `ex_slop` collection; see the
# rule review on issue #139 for why the rest of that library was not adopted.
defmodule LocalCents.CredoChecks.CaseOnBoolean do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      A `case` whose only clauses are `true` and `false` reads better as
      `if`/`else` — the reader shouldn't have to scan two clauses to work out
      which branch is the truthy one. This is a common shape in machine-written
      Elixir.

          # bad
          case connected?(socket) do
            true -> :live
            false -> :static
          end

          # good
          if connected?(socket), do: :live, else: :static
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, meta, [_subject, [do: clauses]]} = ast, issues, issue_meta)
       when is_list(clauses) do
    if boolean_clauses?(clauses) do
      {ast, [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # True only for exactly two clauses whose head patterns are the literal
  # booleans `true` and `false` (in either order). A guarded head (`true when ...`)
  # or an extra `_ ->` catch-all yields a non-boolean pattern, so it falls through
  # — those are genuine `case`s, not a disguised `if`.
  defp boolean_clauses?([_, _] = clauses) do
    patterns = clauses |> Enum.map(&clause_pattern/1) |> Enum.sort()
    patterns == [false, true]
  end

  defp boolean_clauses?(_), do: false

  defp clause_pattern({:->, _meta, [[pattern], _body]}) when pattern in [true, false], do: pattern
  defp clause_pattern(_), do: nil

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`case` on a boolean (`true`/`false` clauses) reads better as `if`/`else`.",
      trigger: "case",
      line_no: line_no
    )
  end
end
