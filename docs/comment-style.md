# Comment Style

This guide is our house standard for **code comments** — the `#` notes that live
in the source, and the reviewer-facing rationale that does _not_. It is the
companion to [`moduledoc-style.md`](moduledoc-style.md): that guide owns
`@moduledoc`/`@typedoc`; this one owns everything below the doc line.

It exists because a comment is cheap to write and permanent to read. Left
un-calibrated, a codebase accretes three-to-five-line blocks that explain _this
change to the current reviewer_ rather than _the code to its future maintainer_,
and the signal drowns. This guide draws the line.

It is written for both human contributors and AI agents. When you add a comment,
follow it; when you review one, hold it to this bar.

## Where each _why_ lives

Four places hold "why," and each has a different audience. Put each fact in
exactly one of them and link rather than restate.

- **Moduledoc** — the durable answer to "what is this module and why does it
  exist?", for someone scanning the module list. Owned by
  [`moduledoc-style.md`](moduledoc-style.md).
- **Inline comment** (`#`) — a local, durable "why is _this_ surprising?" for the
  maintainer reading the source. The rest of this guide is about these.
- **ADR** (`docs/adr/`) — the record of a decision: problem, choice,
  alternatives, consequences. A comment _summarizes the outcome and links the
  ADR_; it never relitigates it.
- **PR review comment** — single-use, reviewer-facing rationale: "here's why I
  chose this over the alternative I weighed, for _this_ review." It belongs on
  the pull request, not baked into the source (see
  [Single-use rationale goes to the PR](#single-use-rationale-goes-to-the-pr)).

## Inline comments: why, not what

The one rule that governs every inline comment — the same rule
[`moduledoc-style.md`](moduledoc-style.md) holds moduledocs to:

> **Explain the _why_, not the _what_.** The reader can already see the code.

A comment earns its space by saying what the code cannot: an invariant, a race
the code guards against, a non-obvious ordering, why the obvious approach is
wrong _and stays wrong_. If a sentence would still be true after you deleted the
code beneath it and rewrote it differently, it's probably a durable _why_ and
worth keeping. If it merely narrates the line below, cut it.

**Never open a comment by restating the signature.** The most common padding we
produce is a first clause that re-says the function name before getting to the
point:

```elixir
# Not this — the first clause is the signature spelled out in prose:
# The <select> options as {name, id} pairs; a blank option (Uncategorized) is
# supplied by Bond.select itself.
defp category_options(categories), do: Enum.map(categories, &{&1.name, &1.id})

# This — lead with the load-bearing why, drop the restatement:
# The blank "Uncategorized" option is supplied by Bond.select itself, so it is
# absent here.
defp category_options(categories), do: Enum.map(categories, &{&1.name, &1.id})
```

### Private functions

Elixir has no documentation channel for a `defp` — `@doc` on a private function
[warns and is discarded](https://elixir.hexdocs.pm/writing-documentation.html),
so a `#` comment is the _only_ way to leave a maintainer a note. The official
guide encourages exactly that "whenever it will add relevant information." So:

- **Comment a private function when it carries non-obvious _why_** — a race it
  tolerates, an ordering guarantee, a domain rule the signature can't show. Much
  of `LocalCents.Tracking` and the LiveViews does this well.
- **Hold it to the same why-not-what bar** — a `defp` whose name already tells
  the whole story (`present?/1`, `find_expense/2`) needs no comment.
- **A `defp` that needs _heavy_ explanation is a smell.** The Elixir community's
  heuristic: if a private function is complex enough that you feel you must
  document it at length, it is likely worth extracting into its own module with a
  real moduledoc. Reach for extraction before a long comment block.

## Single-use rationale goes to the PR

Some rationale is real and worth writing down, but only for the person reviewing
_this change_ — "I chose this approach over the obvious alternative because X." It
is consumed once, at review time, and adds nothing to a maintainer six months
later. **Do not bake it into the source.** Post it as a PR review comment on the
relevant line, before the human reviews, so the reviewer gets the context without
the code accreting a one-off explanation.

Authors — human and AI — are explicitly **granted the latitude to omit** such
single-use notes from the code and route them to the PR instead. This is a grant,
not a mandate: use it when a line genuinely warrants review context, not as a
reflex on every diff.

An agent can attach a line-anchored comment right after opening the PR:

```sh
gh api repos/{owner}/{repo}/pulls/{pull_number}/comments \
  -f body="Chose a full replace here over a merge so a blank field is an explicit clear — see ADR 0008." \
  -f commit_id="$(git rev-parse HEAD)" \
  -f path="lib/local_cents/tracking/expense.ex" \
  -F line=104 \
  -f side="RIGHT"
```

The test for which way a note goes is the same one from
[why, not what](#inline-comments-why-not-what): _would a future reader of this
source file want it?_ If yes, it's a durable inline comment. If it only helps the
current reviewer, it's a PR comment.

## Future-work notes go to issues

A "we'll refine this in a later ticket" aside is neither durable why nor
review-time rationale — it is a task, and tasks belong in
[GitHub Issues](agents/issue-tracker.md), not the source. A comment that names
future work rots the moment the work lands elsewhere. Open an issue; link it from
the comment only if the code genuinely needs to point a reader at the tracked
limitation, otherwise leave the code to speak for itself.

## Mechanics

- One space after the leading `#`; comments longer than a word are capitalized
  and punctuated as full sentences (the community convention, and what the
  codebase already follows).
- Backtick domain concepts (`` `Book` ``, `` `Expense` ``) and link ADRs by
  rendered page, matching [`moduledoc-style.md`](moduledoc-style.md).
- Prefer expressive code to a comment: convey intent through naming and structure
  first, and comment only what naming cannot carry.
