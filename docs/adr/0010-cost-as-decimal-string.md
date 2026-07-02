# Cost as Decimal String

## Problem Statement

An Expense's Cost must be stored inside the Automerge document, but **Automerge has
no native decimal type** (its scalars are ints, floats, strings, booleans,
timestamps, counters, bytes). [ADR 0002](0002-expense-attributes.md) calls for a
"decimal value" — how is that represented in the CRDT without corrupting the
honest-totals guarantee the domain depends on?

## Decision

Cost is stored as a **decimal string** (e.g. `"12.34"`) in the Automerge document,
parsed with Elixir's `Decimal` library for arithmetic and formatting. It is
**`nil` / absent when unknown** (see [ADR 0008](0008-mvp-expense-shape.md)),
distinct from `"0"`.

Chosen over:

- **Integer minor units (cents)** — exact and simple, but bakes in a fixed number
  of decimal places (2). We expect to support multiple currencies later, whose
  minor-unit counts vary (0, 2, 3), and don't want that assumption embedded in
  every stored value.
- **Float (F64)** — rejected: floating-point money accumulates rounding error,
  corrupting exactly the totals the domain protects.

Decimal-string keeps values exact, stays agnostic about minor-unit placement, and
is faithful to ADR 0002's "decimal value." Summation parses to `Decimal` and adds
exactly; nil costs are excluded from sums (per ADR 0008), preserving honest
reconciliation to the grand total.

## Consequences & Tradeoffs

- Every read that does math or formatting parses the string to `Decimal` — a small
  cost paid for exactness and future currency flexibility.
- Multi-currency itself remains deferred (single USD currency per Book today, per
  ADR 0002); this decision only avoids foreclosing it in the stored representation.
- Refines [ADR 0002](0002-expense-attributes.md); complements the nil-when-absent
  rule in [ADR 0008](0008-mvp-expense-shape.md).
