# MVP Expense Shape

## Problem Statement

Which attributes make up an Expense in the MVP, which are required, and how do we
represent a *missing* cost — given that quick entry deliberately lets a user save
an Expense before every field is known?

## Decision

The MVP Expense has **four fields**:

| Field | Status |
|---|---|
| **Date** | Required; defaults to today |
| **Description** | Required |
| **Cost** | Optional; **nil when absent — never defaulted to zero** |
| **Category** | Optional; absence rendered as Uncategorized (see [ADR 0005](0005-categories-not-tags.md)) |

**Notes** and **Attachments** (from [ADR 0002](0002-expense-attributes.md)) are
**deferred**. Attachments especially need their own design pass, because binary
blobs stored inside the Automerge CRDT would bloat the syncable document.

**Cost is nil-when-absent for the same reason Category uses a computed absence:** a
missing value must not masquerade as a real one. Defaulting cost to zero would
(a) silently understate the grand total and (b) make a genuine $0 Expense
indistinguishable from one whose amount simply hasn't been entered yet. Nil keeps
totals honest — sums are computed over *present* costs — and yields a "needs an
amount" worklist, the sibling of the Uncategorized worklist.

The MVP therefore has **two independent "needs attention" axes — missing cost and
missing category — both surfaced truthfully rather than faked.** There is no
separate first-class "draft" entity; incompleteness is simply these nil fields.

## Consequences & Tradeoffs

- Sums must skip nil costs — the same "compute over what's present" logic the
  Uncategorized bucket already uses.
- Two worklists (needs-amount, needs-category) fall out for free.
- **Considered and rejected:** cost defaulted to zero (understates totals,
  conflates free vs. unentered); cost required (breaks the quick, save-now capture
  flow the user wants).
- Refines [ADR 0002](0002-expense-attributes.md).
