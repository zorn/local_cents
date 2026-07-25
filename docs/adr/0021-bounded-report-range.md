# Bounded Report Range

## Problem Statement

[ADR 0020](0020-bounded-time-series-in-review.md) fixed the **Report**'s span at the
*whole Book* — columns run contiguously from the earliest to the latest populated
**Month** — and deferred **date-range filtering**. Building the Report view
([issue #132](https://github.com/zorn/local_cents/issues/132)) and prototyping the
Category × Month matrix against the seeded twelve-month demo Books surfaced that a
whole-Book matrix is wider than the everyday question wants: a person opening a
Report usually cares about *recent* spending, and a 12- or 24-column grid spends
horizontal space (and the reader's scroll) on months they did not ask to see.

A trailing-range selector narrows the matrix. But adding one crosses two lines
ADR 0020 drew — the whole-Book span, and the deferral of range filtering — so the
choice is recorded here rather than made silently.

## Decision Made

**The Report gains a bounded *Report range* — a trailing range measured from the
current Month.** The user picks the last *N* Months (presets **3 · 6 · 12 · 24**) or
**All** (the whole-Book span ADR 0020 defined). The default is **6**. The selection is
carried in the Report view's URL (e.g. `?range=6`), so it is reload-stable and
shareable, and changing it re-runs the asynchronous compute for the new range.

The range redefines the *entire* Report, not just which columns show:

- **Columns** are the Months in range.
- **Every total reconciles to the range.** The per-Month column totals, the grand
  total, and the right-hand per-Category **Total** column all sum only what is in
  range — so that Total reads as *spending within the range*, not lifetime. Only the
  **All** range recovers the lifetime figure. This is the only rule under which the
  grand-total corner still equals the sum of its columns.
- **Anchored to today**, current Month inclusive (last 6 = this Month + 5 prior), and
  **clamped to the Book's earliest Expense** — a Book younger than the range shows
  only the Months that exist (no empty pre-Book padding), and a stale Book honestly
  shows trailing empty Months rather than hiding *when* activity stopped.

**The `Tracking` read model owns it.** `Tracking.report/1` becomes `report/2`, gaining
a `:range` option (`{:trailing_months, pos_integer} | :all`) and an injectable `:now`.
`LocalCents.Tracking.Report.compute/2` filters Expenses to the range before folding,
so it computes only what is shown. A notable contract change: `report` now **reads a
clock** — its prior moduledoc claim that it "reads no clock, so it takes no options"
no longer holds, because a trailing range is defined relative to *now*.

The concept is named **range**, deliberately *not* "window": a **window** in this app
is a native desktop window (see [ADR 0006](0006-multi-window-desktop-shell.md)), so
"report window" would misread. See the **Report range** entry in
[`CONTEXT.md`](../../CONTEXT.md).

This **amends ADR 0020**: its whole-Book span becomes the **All** preset rather than
the only mode. Its deferral of *unbounded* / arbitrary custom ranges still stands —
the presets are a small, fixed, bounded set, in the same spirit in which 0020 pulled a
*bounded* per-Month time-series into the MVP.

## Consequences & Tradeoffs

* **Considered:** keeping whole-Book-only (ADR 0020 as written). Rejected — it taxes
  the common case (recent spending) with a wide grid the reader must scroll past to
  reach the months they care about.
* **Considered:** an arbitrary custom start/end date range. Rejected — that is exactly
  the *unbounded* filtering ADR 0020 deferred on purpose; a handful of trailing presets
  captures the everyday value for a fraction of the surface area.
* **Considered:** windowing in the view — compute the whole-Book Report, then slice
  columns and re-sum in the LiveView. Rejected — re-deriving reconciled row/column/grand
  totals belongs in the read model, not scattered in the view, and computing a whole-Book
  matrix only to discard most of it fights the very async-load goal that motivated
  loading the Report off the mount path.
* **Accepted:** `report` now depends on a clock. Determinism is preserved through the
  injectable `:now` seam — the same one the commands and `LocalCents.DemoSeeding`
  already use — so tests pass a fixed time and the fold stays pure.
* **Accepted:** the right-hand **Total** column's meaning is range-dependent (lifetime
  only under **All**). The range selector sitting directly above the matrix makes the
  current scope explicit, so the number is never read out of context.
* **Easier:** the default 6-Month range means a fresh open computes only ~6 columns —
  a cheaper first paint that complements the async load.
