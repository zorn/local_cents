# A Global Fallback for Unhandled LiveView Messages

## Problem Statement

Every LiveView that subscribes to a Book's PubSub topic receives **every** signal
broadcast on it. [ADR 0018](0018-category-assignment-through-the-editor.md) added a
second signal — `{:categories_updated, book_id}` alongside `{:book_updated, book_id}`
— and noted that uninterested subscribers "simply ignore `:categories_updated` with a
no-op clause." That works, but it exposes a scaling problem as the signal vocabulary
grows.

The root cause is a sharp edge in `Phoenix.LiveView.Channel` (v1.2.6,
`view_handle_info/2`): a LiveView that defines **no** `handle_info/2` gets the
framework's own log-and-ignore fallback, but the moment it defines **any**
`handle_info/2` clause it opts out of that fallback and becomes responsible for
**every** message its process receives. An unmatched message is then a
`FunctionClauseError` that crashes the view (the client silently reconnects and
remounts). So any view that handles even one signal must also hand-write a no-op
clause for every *other* signal on its topics — purely to avoid crashing.

With three subscribing views today and a handful of signals, that is already N×M
boilerplate, and it grows every time a new signal type is introduced: a new signal
means auditing and touching every subscriber that does not care about it, or risk a
crash. Nobody is going to write a bespoke `handle_info` clause for every possible
message shape, so the default posture should be "ignore what I don't handle," not
"crash on what I don't handle."

## Decision Made

**Inject a catch-all `handle_info/2` into every LiveView through the shared
`LocalCentsWeb.live_view/0` macro**, appended *after* each view's own clauses via a
`@before_compile` hook (`LocalCentsWeb.LiveViewUnhandledInfo`). The clause logs the
message at `:debug` and returns `{:noreply, socket}`.

- **Why `@before_compile` and not an inline clause in the `use` macro:** clause order
  follows definition order, and `use LocalCentsWeb, :live_view` sits at the top of a
  module. A catch-all injected inline would be defined *first* and shadow every
  specific handler the view writes below it — the documented anti-pattern. A
  `@before_compile` hook emits its code *after* the module body, so specific clauses
  match first and the fallback only catches what falls through.
- **Why log at `:debug` rather than swallow silently:** a silent catch-all also
  hides genuine bugs — a typo'd pattern or a message you *meant* to handle. Logging
  at `:debug` keeps the "you forgot to handle X" signal available in development while
  staying quiet in production (prod runs at `:info`). This mirrors the framework's own
  fallback behavior, which we lose the instant we define a clause.
- **Explicit no-op clauses remain a valid, encouraged choice for *known* ignores.**
  The catch-all is the safety net for the long tail and for not-yet-triaged future
  signals. When a view *deliberately* ignores a specific, known signal — like
  `:categories_updated` in `LibraryLive` and `BookCategoriesLive` — an explicit
  `handle_info` clause with a comment still earns its keep: it documents the intent
  and avoids a misleading "unhandled" debug line for a message that is, in fact,
  expected. The existing `:categories_updated` no-op clauses are kept for that reason.

This **refines ADR 0018**: its "ignore with a no-op clause" guidance becomes "ignore
with an *optional* no-op clause for documented intent; the injected fallback covers
everything else." ADR 0011's topic-per-Book model is unchanged.

## Consequences & Tradeoffs

* **Considered:** keeping per-signal no-op clauses as the only mechanism (status quo).
  Rejected — it scales as N subscribers × M ignored signals, and a *forgotten* no-op
  is a crash rather than a warning, so the failure mode is severe and easy to hit.
* **Considered:** splitting signals onto finer-grained topics so uninterested views
  never receive them (e.g. a separate `book:<id>:categories` topic). Rejected for now
  — it reopens ADR 0018's deliberate choice to make `:categories_updated` *additive on
  the same topic*, and it pushes complexity onto the broadcaster and multiplies
  subscriptions to solve a problem the fallback solves in one place.
* **Considered:** a bare, silent catch-all (`handle_info(_, socket)` → `{:noreply,
  socket}`) in each view or the macro. Rejected — it swallows real bugs with no trace.
  The logging fallback keeps the diagnostic value.
* **Accepted:** every LiveView now exports `handle_info/2` (the injected clause), so
  all views take the "view is responsible" channel path rather than the framework
  fallback path. This is intentional and uniform; our injected clause reproduces the
  framework's log-and-ignore behavior.
* **Accepted:** a genuinely forgotten handler no longer crashes loudly — it logs at
  `:debug` and is ignored. That is the right trade for a desktop app where a crash-remount
  is worse than a missed update, but it does mean a dropped handler is quieter. The
  `:debug` log and targeted tests
  (`test/local_cents_web/live_view_unhandled_info_test.exs`) are the guardrails.
* **Easier:** introducing a new PubSub signal no longer requires touching every
  subscriber that ignores it. Views handle the signals they care about and inherit safe
  ignoring of the rest for free.
