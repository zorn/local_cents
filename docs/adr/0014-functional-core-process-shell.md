# Functional Core, Process Shell

## Problem Statement

Issue #62 is where the first real domain logic lands — expense validation, the
non-negative decimal `Cost`, the `nil`-cost rule, the full-replace edit, delete.
Until now a Book's mutation logic lived inside the Rust NIFs
(`ExAutomerge.add_expense/rename` hydrated the document, mutated it, and
reconciled), and the per-Book `BookServer` GenServer coordinated persistence and
broadcast. If #62's rules were added the same way, domain logic would be split
across a Rust crate and a GenServer's `handle_call/3` — untestable without a NIF
and a running process, and impossible to reason about as plain data. Where should
that logic live?

## Decision Made

Adopt a **functional core / process shell** split (Gary Bernhardt's "functional
core, imperative shell"; Saša Jurić's "separate the functional core from the
process shell").

- **`LocalCents.Tracking.BookDocument` is the functional core.** It holds a Book's
  decoded contents (name + `[Expense]`) as plain Elixir data and implements every
  command — `add_expense`, `edit_expense`, `delete_expense`, `rename` — as a pure
  function: data in, `{:ok, document, result}` or `{:error, …}` out. No process, no
  I/O, no NIF, and **no clock** (see below). All validation runs here via
  `Expense.changeset/3`.

- **`LocalCents.Tracking.ExAutomerge` is reduced to a dumb codec.** It no longer
  owns any domain operation. It exposes `decode/1` (bytes → plain state map) and a
  single mutation `reconcile/3` (prior bytes + whole new state + time → new bytes),
  plus `merge/2` and the cheap `document_name/1` / `document_updated_at/1` reads.
  Adding, editing, deleting an expense and renaming the Book are all just "compute a
  new state and apply it"; `autosurgeon::reconcile` diffs old against new and records
  the minimal CRDT operations.

- **`BookServer` is the thin process shell.** Each command is
  `decode → BookDocument.<command> → apply → persist → broadcast`. It orchestrates
  side effects and owns none of the rules.

- **Clocks are injected, never read by the core.** Two distinct time inputs enter
  at the boundary (`LocalCents.Tracking`): a UTC `now` for the Automerge change
  stamp (see [ADR 0012](0012-book-last-updated-timestamp.md)) and a **local
  `today`** for an expense's default date. The core reads neither. This is what
  makes "today" correct for the *user's* timezone: on the desktop the boundary
  defaults it to the machine date, and a future web caller passes the browser's
  date. A core that called `Date.utc_today/0` would silently use the server's zone.

The upshot: the entire domain model is exercised by fast, `async: true`,
process-free unit tests (`BookDocumentTest`), with the GenServer/NIF integration
covered thinly on top. This deliberately moves the project *away* from broad
async/process tests toward plain-data ones.

## Consequences & Tradeoffs

- **Considered and rejected:** a *validation-only* pure module in front of granular
  Rust mutation NIFs. Less refactoring, but domain mutation would stay split
  between Elixir (validate) and Rust (mutate) — the exact seam this avoids.
- **A single general `reconcile/3`** replaces the per-operation `add_expense`/`rename`
  NIFs. Every write ships the whole document state across the NIF boundary and
  reconciles it; fine at MVP scale, and flagged (with ADR 0007) for later
  performance work on very large Books.
- **Rust owns no business rules**, so a rule change is an Elixir-only change with no
  recompile of the crate.
- Establishes the pattern future contexts should follow; the clock-injection rule
  in particular is what keeps the core correct once the same code runs server-side
  for multiple users on the web.
