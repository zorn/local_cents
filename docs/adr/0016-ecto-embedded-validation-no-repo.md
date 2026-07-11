# Ecto for Validation, No Repo

## Problem Statement

LocalCents was generated **without** a database: expenses live inside a per-Book
Automerge document, and [ADR 0007](0007-book-runtime-and-persistence.md)
deliberately rules out SQL/SQLite for the MVP. So `ecto` was not a dependency. Yet
#62's Expense needs real casting and validation — string form input to `Date` and
`Decimal`, required `date`/`description`, non-negative-or-nil `cost` — and #63's
editor wants form-native errors. Do we hand-roll that, or add a validation library
to a project that intentionally has no database stack?

## Decision Made

**Add `ecto` (and its `decimal` dependency) and model `Expense` as an
`embedded_schema` with a `changeset/3` — but no `ecto_sql`, no `Repo`, no
database.** Ecto is used purely as a casting-and-validation library. The store
remains the Automerge document; `BookDocument` runs the changeset and, on success,
holds the resulting struct (`date` as `Date`, `cost` as `Decimal`) as in-memory
domain state.

This buys, for little code: declarative `cast` of form strings to typed values,
`validate_required` / `validate_number`, and changesets that drop straight into
the #63 editor via `to_form` and `<.input>`. `Decimal` is needed regardless — ADR
0010 already commits to it — so the only real question was validation ergonomics,
and Ecto's embedded-schema/schemaless-changeset pattern is a well-worn Phoenix idiom
that does not imply a database.

## Consequences & Tradeoffs

- **Considered and rejected:** hand-rolled validation returning tagged tuples plus
  only `{:decimal}`. Keeps the stack minimal and framework-free, but re-implements
  casting and hands the editor a non-changeset to adapt. We chose ergonomics for
  the editor now, and can revisit if Ecto proves to pull its weight poorly.
- **A future reader will double-take at "Ecto with no database"** — hence this
  record. The line to hold: `ecto` yes, `ecto_sql`/`Repo` no. If a `Repo` is ever
  proposed, that is a separate, larger decision (and would reopen ADR 0007).
- Pre-deployment, adding the dependency is low-risk; the project is not yet
  shipped and the schema is still churning.
