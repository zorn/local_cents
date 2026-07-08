# LocalCents MVP Proposal

**Status:** Accepted — in progress. _(Flip to `Implemented / Archived` once the
MVP ships. From that point this document is history: the ADRs, `CONTEXT.md`, and
the code are the source of truth, and where they disagree with this proposal, they
win.)_

This document is the agreed scope for the first buildable slice of LocalCents,
forged in a design session. It is a **summary and index** — the binding decisions
live in [`CONTEXT.md`](../../CONTEXT.md) (the glossary) and in the ADRs under
[`docs/adr/`](../adr/about.md), which each section links to. Where this document and an ADR
disagree, the ADR wins.

Implementation is tracked in the Wayfinder map
[#58](https://github.com/zorn/local_cents/issues/58), where the in-scope build is
carved into dependency-ordered sub-issues.

## The MVP's single job

> A person can **reliably capture and review** their household (and side-hustle)
> expenses on **one device**, across multiple **Books**.

Everything below serves that sentence. The riskiest, least-defined parts of the
larger vision — sync and conflict resolution — are deliberately **out of scope**
so this slice stays shippable and the hard parts get their own focused design pass
later.

## Scope boundary

- **macOS desktop only** (Tauri). The web mirror is aspirational and deferred.
- **Single device. No Automerge sync yet** — that is the next milestone, not the
  MVP.
- **Multiple Books, multi-window** desktop shell.

## The build (in scope)

### Books, library, and the desktop shell
See [ADR 0006](../adr/0006-multi-window-desktop-shell.md) and
[ADR 0007](../adr/0007-book-runtime-and-persistence.md).

- Multiple **Books**. Launching the app opens a **library window** listing them.
  Creating a Book uses an **inline name input** in the library → submit → the Book
  is created *and* its document window opens.
- **One document window per Book**; different Books can be open at once (the
  personal *Family Expenses* + side-hustle *Business Expenses* scenario). Opening
  an already-open Book **focuses** its window.
- **Library actions propagate to open windows**: delete → the open window closes
  with a notice; rename → live title update.
- Each place is a real **LiveView route** (`/library`, `/books/:id`). Native
  windows are created by **Elixir publishing over the elixirkit PubSub bridge**;
  Rust only manages window chrome. No Tauri commands, no new IPC channel.
- **Runtime:** a **per-Book GenServer** is the single source of truth for an open
  Book; LiveViews subscribe via Phoenix.PubSub and send commands. This tolerates
  multiple concurrent viewers (needed for the web future).
- **Persistence:** one Automerge document per Book, stored as a **`.lcbook`** file
  (see [ADR 0009](../adr/0009-book-file-format.md)) in the macOS application-support
  directory. The library is the enumeration of that directory.

### Expenses
See [ADR 0008](../adr/0008-mvp-expense-shape.md) and
[ADR 0010](../adr/0010-cost-as-decimal-string.md).

- Fields: **Date** (required, defaults today), **Description** (required),
  **Cost** (optional; **decimal string**, `nil` when absent — never `0`),
  **Category** (optional).
- **Capture** has two paths: a deliberately **dumb quick-add** (an amount + the
  rest is the description, date = today, no category, no cleverness) and a
  **reliable full editor** (the primary path).
- **Edit** via the full editor; **delete** is a hard delete behind a confirmation.
- Two honest "needs attention" axes — missing cost and missing category — surfaced
  truthfully, never faked. No separate "draft" entity.

### Categories
See [ADR 0005](../adr/0005-categories-not-tags.md).

- **Categories, not tags.** At most one Category per Expense; optional.
- **No seeded categories** — a new Book starts empty; suggestions live in help
  docs. Categories are a curated **hard list** managed in a **dedicated view**;
  the expense editor only *selects* from existing categories (no inline creation).
- **Delete freely** → affected Expenses become **Uncategorized**. The management
  view shows an Expense count per Category and a deletion nudge.
- **Uncategorized** is a **computed absence**, not an entity — always a bucket in
  totals (so they reconcile) and the worklist for re-filing.

### Review
- The document window shows the **expense list** (sorted by date) and a
  **group-by-category totals** summary: each Category's total, the Uncategorized
  bucket, a needs-amount indicator, all **reconciling to a grand total**.
- **Numbers and tables only — no charts.** Time-series visualization and
  date-range filtering are deferred.

### Money
See [ADR 0002](../adr/0002-expense-attributes.md) and
[ADR 0010](../adr/0010-cost-as-decimal-string.md).

- **Single currency per Book**, defaulted to **USD**, no picker UI in the MVP.
  Cost stored as a decimal string, parsed with `Decimal`.

### First-run demo Books
- On first launch (empty books directory **and** a not-yet-seeded flag),
  **generate two editable demo Books** — *Family Expenses* and *Business
  Expenses* — from a **seed module using the `Tracking` API** (so they always
  match the current schema and exercise real code paths). Seeded **once**, gated by
  a persisted flag so demos don't resurrect after deletion. The Business Expenses
  seed expresses its old `client:*` tag idea with **categories** instead.

### Testing
- **Domain tests** against the `Tracking` context (ExUnit, extending
  `test/local_cents/tracking_test.exs`): create/edit/delete, category assignment,
  delete-→-uncategorized, totals reconciliation, nil-cost handling.
- **UI feature tests** via `LocalCentsWeb.FeatureCase` (PhoenixTest): drive
  add/edit/categorize/delete as a user and assert the UI responds.
- Patterns are still forming — **best-effort, refined under review.**

### UI components
- New/changed UI follows the **Bond + Storybook** pattern (component under
  `lib/local_cents_web/bond/`, mirrored `*.story.exs`). Expect to build new
  components and **rework `expense_cell` and `tag_pill`** from the old tags design
  to the single-Category model.

## Explicitly deferred (not the MVP)

- **Automerge sync + conflict-resolution UX** (the next milestone).
- **Web version** (architecture keeps the door open via route-per-place).
- **Tags** — possibly indefinitely.
- **Notes** and **Attachments** on expenses.
- **Spend-over-time charts / visualization**; date-range filtering.
- **Currency picker / multi-currency.**
- **Bulk-reassign** expenses between categories; **category merge**.
- **Credit-card statement import**; **budgeting / goal tracking**.
- **Pre-built demo Book files** (we generate at runtime while the schema churns);
  a hidden **re-seed** tool.

## Open items (to decide during the build, not blockers)

- **GenServer supervision tree / process registry** design ([ADR 0007](../adr/0007-book-runtime-and-persistence.md)).
- **Reverse-DNS UTI registration** (`com.zornlabs.localcents.book`) for when
  `.lcbook` files become user-facing ([ADR 0009](../adr/0009-book-file-format.md)).
- **Performance testing** for large Books / libraries, and possibly incremental
  persistence ([ADR 0007](../adr/0007-book-runtime-and-persistence.md)).

## Decision index

- Glossary: [`CONTEXT.md`](../../CONTEXT.md)
- [ADR 0002 — Expense Attributes](../adr/0002-expense-attributes.md) (amended)
- [ADR 0005 — Categories Not Tags](../adr/0005-categories-not-tags.md)
- [ADR 0006 — Multi-Window Desktop Shell](../adr/0006-multi-window-desktop-shell.md)
- [ADR 0007 — Book Runtime and Persistence](../adr/0007-book-runtime-and-persistence.md)
- [ADR 0008 — MVP Expense Shape](../adr/0008-mvp-expense-shape.md)
- [ADR 0009 — Book File Format](../adr/0009-book-file-format.md)
- [ADR 0010 — Cost as Decimal String](../adr/0010-cost-as-decimal-string.md)
