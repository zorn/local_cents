# Unhandled Messages Warning

## Problem Statement

[ADR 0019](0019-liveview-unhandled-info-fallback.md) has the injected catch-all
`handle_info/2` log at `:debug` — mirroring the framework fallback it replaces — and
accepts the cost that a forgotten handler is now "quieter." That cost is larger than
`:debug` admits, because the same ADR encourages **explicit** no-op clauses for known
ignores. Those were written, so nothing in the app's own traffic reaches the fallback:
every message that does is one nobody anticipated, usually a handler someone forgot,
leaving a view showing stale numbers. Production runs at `:info`, so that event left
no trace at all.

## Decision Made

**The fallback logs at `:warning`.** Everything else about ADR 0019 is unchanged — the
`@before_compile` injection, the clause ordering, ignoring rather than crashing, and
explicit no-op clauses as the way to document a known ignore.

The framework-parity argument does not survive the amendment: that fallback fires when
a view defines no `handle_info/2` at all, ours only after every explicit clause has
declined. Same shape, different trigger.

Development is unchanged, since the level there is already `:debug`. The gain is
forensic — the event now survives into a production log at a level that says someone
should look. If a message source we do not control later routes through a LiveView
mailbox, it will warn; the fix is an explicit no-op clause, which is already how a
known ignore gets recorded.
