# Report Refreshes On Demand

## Problem Statement

[ADR 0017](0017-in-window-secondary-views.md) established that every secondary Book
view re-reads its own data on the `{:book_updated}` PubSub broadcast — each page is an
independent live subscriber, so the Categories and Expenses views stay fresh as the
Book is edited elsewhere. That is right for those views: they *are* the editing
surfaces, and a live refresh is what the user expects while curating.

The Report view ([issue #132](https://github.com/zorn/local_cents/issues/132)) is a
different animal. It is a **read-only analytical surface** built on an expensive,
whole-slice fold (the **Report** read model, [ADR 0020](0020-bounded-time-series-in-review.md)
/ [issue #68](https://github.com/zorn/local_cents/issues/68)) that is loaded
asynchronously off the mount path precisely because it can be non-trivial to compute.
Applying ADR 0017's "re-read on every broadcast" rule literally would (a) re-run that
costly fold on *every* unrelated edit, and (b) move the ground under a reader who may
be scrolled deep into a wide matrix comparing two Months — the numbers would shift and
the scroll would jump, unbidden.

## Decision Made

**The Report view does not recompute on `{:book_updated}`.** Instead it marks itself
**stale** and shows a banner with a **Refresh** button, handing the user control over
*when* the numbers move. Refresh re-runs the asynchronous compute, keeping the current
matrix on screen until the new one resolves (no flash back to a loading state).

Two things still happen live, so this defers *only* the matrix recompute:

- A Book **rename** still propagates immediately — `page_title` plus
  `DesktopShell.set_book_title`, matching the other views (the native title bar does
  not follow `page_title` on its own).
- A Book **deleted** elsewhere still redirects to the library at once. That is not
  staleness; the thing is gone.

This **scopes ADR 0017**: "re-read on `{:book_updated}`" governs the *editing* views,
while the Report — a read-only view — **refreshes on demand**. Title propagation and
deletion handling are unchanged from the ADR 0017 mount contract.

## Consequences & Tradeoffs

* **Considered:** following ADR 0017 literally and auto-recomputing on every broadcast.
  Rejected — it re-runs the expensive fold on unrelated edits and disorients a reader by
  shifting the matrix under them.
* **Considered:** auto-recomputing but holding the current matrix and scroll visible
  until the fresh result is ready. Rejected — it still changes the numbers a reader is
  studying without their say-so; unlike an editing surface, a Report has no expectation
  of being live-fresh.
* **Accepted:** the Report can display stale numbers until the user refreshes. The
  banner makes that state explicit and honest rather than silent.
* **Accepted:** the per-page live-subscriber boilerplate from ADR 0017 is still present
  (the page subscribes and handles `{:book_updated}`), but its handler sets a flag and
  updates the title instead of re-reading the report — a deliberate, documented
  divergence a future reader would otherwise "fix."
