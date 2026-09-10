defmodule Mix.Tasks.Guardrail.Review do
  @shortdoc "Fails when a change weakens our Credo/Sobelow guardrails"

  @moduledoc """
  Reads the diff against a base ref and fails if the change would quietly weaken
  our static-analysis guardrails — an added `credo:disable`/`sobelow_skip` comment
  (a brand-new suppression, or the new side of an edited one), or an edit to
  `.credo.exs`, `.sobelow-conf`, or a `.github/workflows/*` file. The detection
  lives in `LocalCents.Guardrail`; this task is only the git plumbing around it.

      $ mix guardrail.review                 # diff HEAD against origin/main
      $ mix guardrail.review --base origin/develop

  CI passes the pull request's base branch so the diff is exactly what the PR
  proposes; see [Coding Standards](https://github.com/zorn/local_cents/blob/main/CODING_STANDARDS.md).

  A red result here is not a bug to route around — it is the gate working. The
  fix is to merge with an admin override (a conscious "I reviewed this guardrail
  change"), not to delete the skip the task points at.

  ## Options

    * `--base` — the ref to diff against. Defaults to `origin/main`.
  """

  use Mix.Task
  use Boundary, classify_to: LocalCents

  alias LocalCents.Guardrail

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [base: :string])
    base = Keyword.get(opts, :base, "origin/main")
    range = "#{base}...HEAD"

    diff = git!(["diff", "--unified=0", range])
    changed_files = String.split(git!(["diff", "--name-only", range]), "\n", trim: true)

    report(Guardrail.review(diff, changed_files))
  end

  defp report([]) do
    Mix.shell().info("Guardrail review passed — no new suppressions or config edits.")
  end

  defp report(violations) do
    Mix.raise(Guardrail.format(violations))
  end

  # `System.cmd/3` raises rather than returning a status when git is absent, so
  # both a missing binary and a non-zero exit surface as a loud failure — the
  # check must never pass by silently reading an empty diff.
  defp git!(args) do
    case System.cmd("git", args, env: [], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> Mix.raise("git #{Enum.join(args, " ")} failed (#{status}):\n#{output}")
    end
  rescue
    ErlangError -> Mix.raise("git is not available on this machine.")
  end
end
