defmodule Mix.Tasks.Guardrail.Review do
  @shortdoc "Flags a change touching our Credo/Sobelow guardrails, for admin review"

  @moduledoc """
  Reads the diff against a base ref and fails if the change touches one of our
  static-analysis surfaces — an added `credo:disable`/`sobelow_skip` comment (a
  brand-new suppression, or the new side of an edited one), or an edit to
  `.credo.exs`, `.sobelow-conf`, or a `.github/workflows/*` file — so an admin
  reviews it before merge. The detection lives in `LocalCents.Guardrail`; this
  task is only the git plumbing around it.

      $ mix guardrail.review                 # diff HEAD against origin/main
      $ mix guardrail.review --base origin/develop

  CI passes the pull request's base branch so the diff is exactly what the PR
  proposes; see [Coding Standards](https://github.com/zorn/local_cents/blob/main/CODING_STANDARDS.md).

  A red result here is the gate working, not a bug to route around: an admin
  reviews the flagged change and merges past the check. The fix is never to delete
  the skip the task points at just to get green.

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

  # A non-zero exit is a loud failure — the check must never pass by silently
  # reading an empty diff. stderr is left unmerged so a git warning on a
  # successful run (line-ending advice, ownership notes) can't slip into the diff
  # or the `--name-only` file list we parse; it prints to the console instead.
  defp git!(args) do
    case System.cmd("git", args, env: []) do
      {output, 0} -> output
      {_output, status} -> Mix.raise("git #{Enum.join(args, " ")} failed (exit #{status}).")
    end
  rescue
    # `System.cmd/3` raises only when the binary itself is missing; any other
    # ErlangError is a real fault and should keep its own message.
    e in ErlangError ->
      if e.original == :enoent do
        Mix.raise("git is not available on this machine.")
      else
        reraise e, __STACKTRACE__
      end
  end
end
