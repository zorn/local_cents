# Expense Identity & Date Encoding

## Problem Statement

[ADR 0008](0008-mvp-expense-shape.md) fixes an Expense's *fields* and
[ADR 0010](0010-cost-as-decimal-string.md) its *cost encoding*, but #62 — where
edit and delete arrive — surfaces two representation questions those left open:
how is a single Expense **addressed** for editing/deleting, and how is its
**date** stored inside the Automerge document? Both bytes-on-disk choices are
sticky (they live in users' `.lcbook` files), so they are recorded deliberately.

## Decision Made

**Identity: each Expense carries a UUID `id`, generated in Elixir at creation.**
Expenses are addressed by that `id` for edit and delete — never by list position.
The id is produced by `Ecto.UUID.generate/0` (the same scheme Book ids use) in the
process shell and handed to the functional core as an argument, so the core stays
pure (see [ADR 0014](0014-functional-core-process-shell.md)).

Positional identity (the Automerge list index) was rejected: an index shifts as
expenses are inserted or removed and, critically, is **not stable under a CRDT
merge** — two devices inserting concurrently would renumber each other's rows, so
an "edit expense #3" or "delete expense #3" command could hit the wrong Expense
after sync. A stable per-Expense id is the only address that survives the merge
future this whole architecture is built for.

**The id must also key the CRDT reconciliation, not just the application API.**
`autosurgeon` reconciles a `Vec` by list *position* unless told otherwise, so the
UUID alone does not buy merge-safety. The stored `Expense` marks its `id` with
`#[key]` (`native/ex_automerge/src/lib.rs`) so autosurgeon matches list elements by
identity: deleting a middle expense removes exactly that element rather than
rewriting every following slot, and a concurrent edit to a different expense
survives the merge. Without the key, our whole-state reconcile would overwrite
objects in place and corrupt concurrent edits — the exact failure Automerge's
operation-level model warns against.

**Date encoding: an ISO-8601 date string (`"YYYY-MM-DD"`).** Stored as a plain
string in the document; parsed to and from a `Date` at the `BookDocument` boundary
(the struct field is a `Date.t()`).

Rejected alternatives:

- **Automerge's `timestamp` scalar** — it models an *instant*, not a *calendar
  day*. Using it would smuggle in a time-of-day and a timezone question for what is
  simply "the day the money was spent."
- **An integer (days since epoch)** — opaque inside the stored document, with no
  readability benefit over the string.

The string choice mirrors the reasoning already blessed for cost in ADR 0010:
human-readable in the CRDT, unambiguous, and faithful to the field's real meaning.

## Consequences & Tradeoffs

- Every read parses `date` (`Date.from_iso8601!/1`) and writes render it
  (`Date.to_iso8601/1`) — a trivial cost paid for a readable, unambiguous document.
- The `id` makes the edit/delete API unambiguous and merge-safe, and gives the UI a
  stable key for a row. It also lets a future feature distinguish an Expense that
  was *deleted* from one that *never existed* via change history (deferred —
  [#104](https://github.com/zorn/local_cents/issues/104)).
- Refines [ADR 0008](0008-mvp-expense-shape.md); complements
  [ADR 0010](0010-cost-as-decimal-string.md).
