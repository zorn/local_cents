# Book Runtime and Persistence

## Problem Statement

While a Book is open it is edited live — by one native window on macOS today, and
potentially several browser tabs on the web later. Where does the authoritative
in-memory state of an open Book live, and how is a Book stored on disk on a single
device?

## Decision

**A per-Book GenServer is the single source of truth for an open Book.** One
process per *open* Book owns the in-memory Automerge document. Every LiveView
viewing that Book **subscribes via Phoenix.PubSub** and sends *commands* (add
expense, edit, categorize) to the process. The process applies each change to the
Automerge document, persists it, and **broadcasts** the new state to all
subscribers, which re-render.

- This supports **N concurrent viewers of one Book without divergence** — critical
  for the future web version — and keeps Book state **out of any LiveView socket**.
- **Lifecycle:** the process starts when a Book is opened and stops (after a final
  persist) when the last viewer disconnects. The **supervision tree and process
  registry design are not yet decided** and are deliberately left open here.

**Persistence: one Automerge document per Book, stored as a file.** The document is
saved to the macOS application-support directory
(`.../books/<book-id>.lcbook` — see [ADR 0009](0009-book-file-format.md) for the
extension). The GenServer loads it on open and writes it on change. **The library is the enumeration of that books directory.** Book identity
is the file id (e.g. a UUID); the human-readable name ("Family Expenses") lives
*inside* the document.

Crucially, **expenses live inside the Automerge CRDT document, not in relational
rows** — so there is no SQL store for expense data in the MVP; you cannot and do
not query into the CRDT with SQL.

## Consequences & Tradeoffs

- **Library enumeration** reads a bit of metadata from each file on load; a small
  sidecar index can be added later only if that proves slow.
- **No SQLite** means cross-Book app settings need a small config file — acceptable
  at MVP scope, where there are almost none.
- **Considered and rejected:** loading the Book into each LiveView's own socket
  assign (simpler, but breaks the moment two viewers exist, which the web future
  guarantees); a relational store for expenses (buys little, since the syncable
  unit is the CRDT blob you'd ship around anyway).
- **Deferred:** this file-based, single-device approach will need revisiting for
  the web version — a browser cannot read the user's local filesystem, so Book
  storage will have to move server-side. That is a separate, larger discussion.
- **Performance is untested at scale (noted, not addressed in the MVP).** The
  entire Automerge document lives in memory in its GenServer and is re-serialized
  and written on change. Very large Books, or a library holding many Books, are
  expected to need dedicated performance testing and possibly incremental
  persistence (append changes rather than rewrite the whole document). Flagged now
  so the concern is on record; not work for the MVP.

## Implementation note (MVP)

The runtime landed in [issue #59](https://github.com/zorn/local_cents/issues/59), and
auto-shutdown-on-last-viewer in
[issue #74](https://github.com/zorn/local_cents/issues/74), with the following choices
for the items left open above:

- **Supervision / registry:** a `LocalCents.Tracking.Supervisor` owns a unique
  `Registry` (`LocalCents.Tracking.BookRegistry`, Book id → process), a
  `LocalCents.Tracking.Presence` tracker, and a `DynamicSupervisor`
  (`LocalCents.Tracking.BookSupervisor`) that starts one
  `LocalCents.Tracking.BookServer` per open Book on demand.
- **Lifecycle:** a `BookServer` starts when a Book is opened in its document window —
  not at app launch; nothing is resident until a Book is opened — persists on every
  change, and **auto-shuts-down once its last viewer disconnects**. A *viewer* is a process that
  registered via `Tracking.register_viewer/1` (a document-window LiveView, through the
  shared `LocalCentsWeb.BookWindow` `on_mount` hook), tracked in `Presence` on a
  dedicated `"book_presence:<id>"` topic — kept distinct from the passive `subscribe/1`
  used by the library, which watches every Book's "Last Updated" without being a
  viewer. The following choices were made and are documented, with the full state
  machine, in [`docs/book-runtime-lifecycle.md`](../book-runtime-lifecycle.md):
    - **Grace period (default 60s, configurable):** the server waits out a short grace
      period before reaping, so the brief zero-viewer gap of an in-window
      `push_navigate` between a Book's views ([ADR 0017](0017-in-window-secondary-views.md))
      doesn't tear the process down and reload from disk.
    - **Reap only after a viewer leaves:** a Book that *never* had a viewer (created but
      unopened, or a bare `open_book/1`) stays resident until `close_book/1` or app
      shutdown, matching the earlier interim behavior for those paths.
    - **Crash resilience:** because `Presence` is a separate process, a crash-restarted
      `BookServer` reads the still-open viewers via `Presence.list/1` at `init` and
      does not reap out from under them.
- **Known deferred edge:** a `BookServer` that crash-restarts *after* all its viewers
  already left comes back with an empty `Presence` list and — since it never observes a
  last-viewer-leaves transition — lingers resident until the app quits. This is
  memory-only and benign; a fix (an ETS marker owned by the supervisor, checked at
  `init` to tell a restart from a first start) is noted but not built.
