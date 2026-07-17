# Bounded Time-Series in Review

## Problem Statement

The MVP proposal's Review section deliberately keeps the review surface simple: a
**group-by-category totals** summary, "numbers and tables only," with
"time-series visualization and date-range filtering" written down as explicitly
**deferred**. Building against that line (#68) surfaced that a single lifetime
total per Category does not deliver the value the Review is for. A person who
back-fills a Book with a year of expenses does not learn much from "Eating Out:
$3,140 all-time" — the question they actually have is *how spending moves over
time*. A flat total cannot answer it.

This forces a scope decision: either ship the flat summary as written and defer
all time-awareness, or pull a **bounded** slice of time-series into the MVP. The
choice is sticky — it shapes the `Tracking` read API and the whole Review view —
and it openly crosses a line the proposal drew, so it is recorded here rather than
changed silently.

## Decision Made

**The MVP Review is a Category × Month matrix, not a flat list.** Categories are
rows, calendar **Months** (see [`CONTEXT.md`](../../CONTEXT.md)) are columns, and
each cell is the total spent in that Category that Month. Row totals give the
per-Category lifetime sum (the original #68 shape, now a strict subset), column
totals give the per-Month grand, and the bottom-right cell is the grand total.
The reconciliation and nil-cost rules from the original Review section carry over
unchanged.

The time-series we pull in is deliberately **bounded**:

- **Per calendar Month only** — no other bucket (week, quarter, rolling window).
- **Whole-Book span** — columns run contiguously from the earliest to the latest
  populated Month, so a Month with no spending appears as an explicit zero rather
  than collapsing. Absence is signal.
- **Spending-only rows** — a Category with no expenses gets no row; Uncategorized
  appears only when a nil-category Expense exists.
- **Per-cell needs-amount** — an Expense with a `nil` cost is surfaced as a count
  on its cell, never summed as `0`, consistent with
  [ADR 0008](0008-mvp-expense-shape.md) / [ADR 0010](0010-cost-as-decimal-string.md).

**What stays deferred is redrawn, not erased.** Still out of the MVP:
**date-range filtering**, **arbitrary/custom ranges**, and **charts**. The Review
remains numbers and tables. This ADR narrows the proposal's blanket "time-series
deferred" to "*unbounded* time-series and filtering deferred; a whole-Book
per-Month breakdown is in."

The `Tracking` context owns the computation as a pure, recomputed-on-demand read
model (a **Report**, see [`CONTEXT.md`](../../CONTEXT.md)); the presentation is a
separate in-window view built later (see [ADR 0017](0017-in-window-secondary-views.md)).

## Consequences & Tradeoffs

* **Considered:** shipping the flat per-Category summary as originally written and
  deferring all time-awareness. Rejected — it is cheaper but does not answer the
  question the Review exists to answer ("where is my spending going *over time*"),
  so it would ship a Review that looks done without being useful.
* **Considered:** a full time-series feature (date-range filters, custom ranges,
  charts) now. Rejected — that is the large, least-defined part the proposal
  deferred on purpose; a whole-Book per-Month matrix captures most of the value
  for a fraction of the surface area.
* **Accepted:** a Book spanning several years produces a wide matrix (36 columns
  over three years). This is a *display* problem for the Report view to solve
  (freeze the Category column, scroll horizontally), not a reason to hide time
  gaps by collapsing empty Months.
* **Accepted:** the proposal's Review section no longer reads literally true and is
  amended to point here so the two documents do not contradict each other.
* **Easier:** the flat per-Category total remains available for free as the
  matrix's row-total column, so nothing from the original #68 scope is lost.
