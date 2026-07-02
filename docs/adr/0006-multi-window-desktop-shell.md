# Multi-Window Desktop Shell

## Problem Statement

A user must be able to work with several Books at once — e.g. a personal *Family
Expenses* Book alongside a *side-hustle LLC* Book — and the MVP is delivered as a
macOS desktop app via Tauri. How is the app structured into windows, and how do
those windows get created, given that today Tauri opens a single webview at
startup?

## Decision

The app is a **multi-window desktop shell**:

- **Two kinds of places, each a real LiveView route:** a **library** (lists all
  Books, create/open) and a **document** (a single open Book) at `/books/:id`.
- **Launching the app opens the library window.** Opening a Book opens a
  **separate document window**; the library window stays open. Multiple document
  windows (for *different* Books) can be open simultaneously.
- **One document window per Book.** Opening a Book that is already open **focuses
  its existing window** rather than spawning a duplicate. Rust tags each window
  with the Book id it holds to enforce this.
- **Library actions propagate to open document windows.** Deleting a Book whose
  document window is open **closes that window** with a brief "this Book was
  deleted" notice; renaming a Book updates its open window's **title live**. Both
  ride the same PubSub broadcast the document window already subscribes to.
- **LiveView drives native window creation.** When the user opens a Book, Elixir
  **publishes an "open a window at route X" message over the existing elixirkit
  PubSub bridge**; Rust's subscriber calls `create_window` with that per-Book URL.
  Rust manages only native window chrome and lifecycle — no `#[tauri::command]`,
  no new IPC channel. Per `CLAUDE.md`, the PubSub bridge is the intended extension
  point.
- **macOS-only for the MVP.** The web mirror is deferred. Because every place is a
  real route, the same LiveViews can later serve web pages, with native windows
  being a desktop-only affordance layered on top; on web, multi-window degrades to
  ordinary navigation / browser tabs.

## Consequences & Tradeoffs

- **Code gap:** today `tauri/src/lib.rs` only creates a window on the startup
  `"ready"` message and points every window at the same URL. This decision
  requires per-route windows and a handler for "open window" messages arriving
  after startup.
- **Accepted loss:** the same Book cannot be viewed in two windows side by side on
  macOS. Judged not worth the confusion of two live edit surfaces on one document.
- **Web constraint carried forward:** on web, two browser windows *could* view the
  same Book, so the underlying architecture must tolerate multiple concurrent
  viewers of one Book (see [ADR 0007](0007-book-runtime-and-persistence.md)) even
  though the Mac shell enforces one window.
- **Considered and rejected:** a single-window app that swaps between library and
  document. Rejected because simultaneous Books (the side-hustle scenario) are a
  core want.
