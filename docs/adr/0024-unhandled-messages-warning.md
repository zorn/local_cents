# Unhandled Messages Warning

## Problem Statement

[ADR 0019](0019-liveview-unhandled-info-fallback.md) has the injected catch-all
`handle_info/2` log at `:debug` — mirroring the framework fallback it replaces.

## Decision Made

**The fallback now logs at `:warning`.** Everything else about ADR 0019 is unchanged — the
`@before_compile` injection, the clause ordering, ignoring rather than crashing, and
explicit no-op clauses as the way to document a known ignore.
