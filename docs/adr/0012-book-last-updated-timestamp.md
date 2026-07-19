# Book Last-Updated Timestamp

## Problem Statement

The library's `book_cell` wants a *Last Updated* subtitle, so a `Book` needs a
"last updated" timestamp ([issue #90](https://github.com/zorn/local_cents/issues/90),
a follow-up from [#61](https://github.com/zorn/local_cents/issues/61)). Everything
is local today, but real multi-device Automerge sync is planned, so the timestamp
must not assume a local filesystem: after a merge it should reflect the *latest
edit*, not the *latest local write*. That rules out the `.lcbook` file's mtime,
which sync will rewrite on every incoming change.

Where should the timestamp come from, and how do we display it?

## Decision Made

**Derive the timestamp from Automerge change metadata, not from a stored field or
file mtime.** A Book's `updated_at` is the **maximum change time across the
document's change history** — read in Rust via `AutoCommit::get_changes/1` and
each `Change`'s `timestamp/0`, taking the max and dropping unset (`0`) stamps
(`native/ex_automerge/src/lib.rs`, `document_updated_at/1`). The research behind
this is captured in
[`docs/research/automerge-last-updated.md`](../research/automerge-last-updated.md).

This is derived history, so it can't drift out of sync with the actual edits and,
after a concurrent merge, it reflects the newest of the merged branch tips.

**Elixir owns the clock; every mutating change is stamped explicitly.** Automerge's
Rust core does *not* default a change's time, so a document written without one has
`timestamp == 0`. The mutating NIFs (`new_document/2`, `rename/3`, `add_expense/4`)
therefore take a `time` (unix seconds) and record it via
`CommitOptions::with_time/1`. The `LocalCents.Tracking` functions supply it from an
injectable `:now` option (a `DateTime` defaulting to `DateTime.utc_now/0`),
converted to whole seconds — the resolution Automerge records. `merge/2` takes no
time: it integrates changes that already carry their own.

> **Update (#62):** the per-operation `rename/3` and `add_expense/4` NIFs named above
> were replaced by a single `reconcile/3` mutation NIF when the tracking context
> moved to a functional-core / process-shell design (see
> [ADR 0014](0014-functional-core-process-shell.html)). The clock-ownership
> mechanism this ADR records is unchanged — `new_document/2` and `reconcile/3` take
> the `time` and stamp it via `CommitOptions::with_time/1` exactly as described.

`updated_at` surfaces on the `LocalCents.Tracking.Book` struct as a
`DateTime.t() | nil` in **UTC**, converted once at the context boundary so the
seconds-vs-milliseconds hazard lives in one place. It is `nil` when no change
carries a usable time, and `book_cell` then omits the subtitle.

**Display: local time via a time zone database, sourced from the browser.** The
struct's UTC value is rendered in the user's local zone. The zone comes from the
browser (`Intl.DateTimeFormat().resolvedOptions().timeZone`) through LiveView
connect params, falling back to UTC on the static first render or an unknown zone.
Conversion uses the [`tz`](https://hex.pm/packages/tz) package as Elixir's
`:time_zone_database`. Format matches the storybook mock: `MM-DD-YYYY h:MM AM/PM`.

**The library subtitle updates live.** `LibraryLive` subscribes to each Book's
PubSub topic and re-reads a Book on `{:book_updated, id}`, so editing a Book in its
document window refreshes the library subtitle rather than leaving it stale.

## Consequences & Tradeoffs

* **Considered and rejected — a stored `updated_at` field in the document.** Simpler
  to read (autosurgeon already hydrates the `BookDoc`), but on a concurrent merge
  Automerge resolves the scalar register by *operation ID, not timestamp value*
  ([Automerge conflicts](https://automerge.org/docs/reference/documents/conflicts/)),
  so the library could show a *stale* time even though a newer edit exists.
  Recovering "latest" would mean reading `getConflicts` and taking a max — the same
  clock-limited computation as deriving from history, plus write-path bookkeeping to
  forget. Derived history avoids all of that.
* **Considered and rejected — file mtime.** Fragile once sync rewrites files; names
  the local write, not the edit. This is the #61 constraint.
* **Considered and rejected — `tzdata`.** It runs a background HTTP updater by
  default, which is wrong for an offline-first desktop app; `tz` makes no network
  calls by default.
* **Accepted limitation:** change times are advisory and come from the writing
  device's clock — Automerge deliberately keeps them out of conflict resolution.
  Under cross-device clock skew, "last updated" is a best-effort heuristic, not an
  authoritative ordering. We display it as information, not as a sort key.
* **Accepted scope growth:** reading the browser time zone via connect params is a
  small new mechanism, but it's reusable by any future local-time display and is the
  first place local time is needed.
* **Mandatory going forward:** any new mutating NIF must stamp its commit with a
  supplied `time`, or that edit will not advance `updated_at`.
