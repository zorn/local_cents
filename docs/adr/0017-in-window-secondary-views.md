# In-Window Secondary Views

## Problem Statement

[ADR 0006](0006-multi-window-desktop-shell.md) established the app's window
model: a library window plus **one native document window per open Book**. But a
Book needs more than one *view* — expenses are the primary surface, and the MVP
also calls for a category management view ([issue #66](https://github.com/zorn/local_cents/issues/66))
and, later, a group-by-category totals view ([issue #68](https://github.com/zorn/local_cents/issues/68)).
ADR 0006 answered "one window per Book" but not "how do a Book's several views
relate to that window." The tempting reading of a multi-window shell is that each
new view is *also* a new native window.

## Decision Made

A Book's secondary views live as **separate LiveView pages navigated inside the
one document window** — not as additional native windows. Concretely:

- Each secondary view is its **own LiveView module at its own route** under the
  Book (e.g. `BookCategoriesLive` at `/books/:id/categories`), kept separate from
  `BookLive` so neither module carries the other's state or grows unwieldy.
- Navigation between a Book's views is a **`push_navigate` within the existing
  native window** — an ordinary in-window route change, not an "open a window"
  message to Rust. The window, and its one-window-per-Book identity from ADR 0006,
  are untouched.
- Every such page **repeats the document-window mount contract**: `open_book/1` →
  `get_book/1` (redirect to the library if the Book is gone) → `subscribe/1`, plus
  a `handle_info({:book_updated, id}, …)` that re-reads its own data and redirects
  if the Book was deleted. Each page is thus an independent live subscriber to the
  same Book.

This **scopes ADR 0006**: "multi-window" governs *Books* (a window per Book, so a
person can see two Books side by side — the side-hustle scenario), while a Book's
*views* are pages within that Book's single window. The unit that earns a native
window is a Book, not a view.

## Consequences & Tradeoffs

* **Considered:** giving each view its own native window (the literal extension of
  ADR 0006). Rejected — it multiplies window-lifecycle and title-bar coordination
  in `DesktopShell`/Rust and fragments a single Book across several windows, for
  views a user visits occasionally to curate rather than keep open. It also
  contradicts the encapsulation goal that one Book = one window.
* **Considered:** folding secondary views into `BookLive` as `live_action`s with
  `push_patch`. Rejected in favor of separate modules for readability and focused,
  per-module tests; the remount cost of `push_navigate` is negligible on desktop.
* **Accepted:** two views of one Book can't sit side by side in the window at once
  — consistent with ADR 0006 already accepting no side-by-side view of one Book.
* **Easier:** [issue #68](https://github.com/zorn/local_cents/issues/68)'s totals
  view inherits this pattern directly — a new LiveView + route + a link in the
  document window, no new window plumbing. Because every view is a real route, the
  deferred web mirror (ADR 0006) gets these pages for free as ordinary navigation.
* **Carried forward:** each page re-establishes its own `open_book`/`subscribe`
  contract, so the per-page mount boilerplate is duplicated rather than shared —
  acceptable now, and a candidate for a small `on_mount` hook if the view count
  grows.
