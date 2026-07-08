# PubSub Topic Naming

## Problem Statement

`Phoenix.PubSub` is how an open Book's `BookServer` notifies its subscribers of
changes (see [ADR 0007](0007-book-runtime-and-persistence.md)). Today there is
exactly one topic, built by `BookServer.topic/1` as `"book:" <> id`. That
convention is implicit and lives in a single function.

As more PubSub-driven features arrive — a library that reacts to Books being
added or removed, per-window notifications, and so on — we will be inventing
topic strings in more places. Without a written scheme, those strings drift:
different separators, ad-hoc prefixes, ids encoded inconsistently, and callers
hand-building strings that get out of sync with the process doing the
broadcasting. This record codifies the naming so topics stay consistent and
discoverable. Raised in review of #75.

## Decision

**Topic strings follow `"<kind>:<id>"` for a specific resource instance, or a
bare `"<kind>"` for a resource collection or global stream.**

- `<kind>` is the singular, lowercase, kebab-case name of the resource the topic
  concerns, using the term as defined in `CONTEXT.md` — e.g. `book`. A `<kind>`
  for a resource the glossary does not yet name must be added to `CONTEXT.md`
  before it is used in a topic, so topic strings never drift ahead of the
  ubiquitous language.
- `:` (colon) is the only separator. Ids follow the last colon.
- `<id>` is the resource's own id string used verbatim. Book ids are opaque,
  topic-safe strings (see [ADR 0009](0009-book-file-format.md)), so no encoding
  or escaping is applied. A `<kind>` that names a single global stream (an
  app-wide event bus, or a collection that has no id) omits the `:<id>` entirely.

Example: `book:0192f3c1-…` (one Book's changes). A future collection stream — say
a not-yet-defined term for "the set of Books changed" — would be a bare
`<kind>`, added to `CONTEXT.md` first.

**The topic string is owned by the module that broadcasts on it, exposed as a
`topic/1` (or `topic/0`) function; callers never hand-build the string.**
`BookServer.topic/1` is the pattern: it is the single source of truth for a
Book's topic, subscribers call it (`Tracking.subscribe/1` already does), and the
`@spec` documents the id type. New PubSub resources add their own `topic`
function next to the process that broadcasts, following the format above. This
keeps the convention codified in code — a caller physically cannot subscribe to
a mistyped topic — with this ADR as the written rationale.

**No shared helper module yet.** With one topic family and an id that needs no
encoding, a `LocalCents.PubSub.Topics` helper would abstract nothing. A helper
becomes warranted only once we have real duplication to remove — e.g. several
resources needing the same id-encoding step, or one resource with multiple topic
families. Until then the per-resource `topic` function is the codification.

This scheme covers only `Phoenix.PubSub`, the in-app bus. The
`ElixirKit.PubSub` bridge to Rust/Tauri is a separate channel with its own
fixed names (`"messages"`) and is out of scope here.

## Consequences & Tradeoffs

- **Discoverability:** to find who listens to a resource, grep for its `topic`
  function; to see the format, read this ADR. No topic strings are scattered
  across call sites.
- **Collision safety:** the `<kind>:` prefix namespaces ids, so a Book id and a
  future resource id can never alias to the same topic.
- **Considered and rejected:** a central `Topics` module or a macro-generated
  registry up front — rejected as premature; it adds indirection before there is
  duplication to justify it, and this ADR plus the per-resource function already
  give us the consistency the registry would enforce.
- **Deferred:** if id encoding ever becomes non-trivial (ids containing `:`, or
  needing URL-encoding), that logic belongs in the owning module's `topic`
  function and this ADR should be revisited with a timestamped addition.
