# Book File Format

## Problem Statement

Each Book is persisted as one Automerge document on disk (see
[ADR 0007](0007-book-runtime-and-persistence.md)). What file extension should
those files use? The obvious `.automerge` is misleading, and a poorly chosen
extension is expensive to change once users have files on disk.

## Decision

Book files use the extension **`.lcbook`**. The bytes inside remain a **standard
Automerge binary document**; the extension is LocalCents' *semantic wrapper*, not
the library's.

- **Not `.automerge`.** Automerge is storage-agnostic — `.automerge` names the
  *encoding*, not *our document*. A `.automerge` file claims to be a generic CRDT
  blob and nothing meaningful would open it. We want the file to identify as a
  *LocalCents Book*.
- **The `book` suffix reinforces the domain.** `Book` is the core noun of the
  domain model (the first term in `CONTEXT.md`); having the file say `book` keeps
  the ubiquitous language visible.
- **The `lc` prefix provides collision-resistance.** A bare `.book` is generic and
  already collides (e.g. Adobe FrameMaker). Namespacing to `.lcbook` makes it
  distinctive. This is a *namespaced* extension, not a risky short/generic one
  like `.lc`.
- **A reverse-DNS UTI (`com.zornlabs.localcents.book`, conforming to
  `public.data`) will be registered later** — in the macOS `Info.plist`
  (`UTExportedTypeDeclarations` + `CFBundleDocumentTypes`, Editor/Owner) — when
  Books become *user-facing* files (export, share, double-click-to-open). For the
  MVP, Books live in the app-support directory and open via the in-app library, so
  the extension string is what matters now; full UTI registration is deferred.

## Consequences & Tradeoffs

- **Considered and rejected:** `.automerge` (names the encoding, not the
  document); `.localcents` (the run-together lowercase brand reads awkwardly
  without a separator); `.localcentsbook` (a clunky mouthful — the `lc` prefix
  already buys the collision-resistance that full verbosity was meant to provide);
  bare `.book` (generic, collides).
- **Sticky by nature:** file identities outlive most other choices, so changing
  this later means migrating users' files — hence recording it deliberately now.
- Refines the persistence format in
  [ADR 0007](0007-book-runtime-and-persistence.md).
