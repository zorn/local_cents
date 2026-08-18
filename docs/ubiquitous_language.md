# LocalCents

The domain glossary for LocalCents — the canonical vocabulary for the app's core concepts. Keep this file to domain nouns only: UI verbs live in [UI Language](ui-language.md), and general software / DDD modeling terms live in [Software Terms](software-terms.md).

## Language

### Tracking (Bounded Context)

**Book**:
The document that all other main domain entities live inside. As the app is starting out we are recording expenses only for the most part, but in time we hope to expand towards income and other financial data.

**Last Updated**:
When a Book was last changed — the time of the most recent edit at its Automerge document's heads, not the moment its file was last written locally. Derived from change history so it survives sync: after a merge it reflects the latest edit across the merged copies rather than the latest local write. Because change times come from the writing device's clock, it is a best-effort, advisory value, not an authoritative ordering (see [ADR 0012](adr/0012-book-last-updated-timestamp.md)).

**Expense**:
A financial transaction that represents money the user has spent. Its **Cost**, when recorded, is non-negative — the MVP tracks spending only, so refunds, credits, and income are out of scope. A missing Cost is left _absent_ rather than recorded as zero, so totals stay honest and a genuine zero-Cost Expense is distinct from one whose amount simply has not been entered yet (see [ADR 0008](adr/0008-mvp-expense-shape.md)).

**Quick-add**:
The deliberately minimal capture path for recording an Expense from a single typed line: an optional trailing amount is the **Cost** and the rest is the **Description**, dated today and **Uncategorized**. It contrasts with the _full editor_, the reliable primary path that also sets Date and Category. Quick-add never blocks — a missing amount is simply absent — and does no clever parsing (no relative dates, currency symbols, or drafts).

**Category**:
A classification of an Expense that answers "what kind of spending is this?" An Expense has _at most one_ Category and may have none — quick entry never blocks on assigning one. Because an Expense carries at most one Category, expenses can be grouped and summed without double-counting. (A future many-per-Expense label — a _tag_ — is a different concept and is out of scope for the MVP.)

**Uncategorized**:
Not a Category entity, but the computed bucket of Expenses that have no Category. It appears as a row in group-by / totals views whenever any Expense is uncategorized, so category totals reconcile to the grand total, and it doubles as the worklist of Expenses that still need a Category. When every Expense is filed, there is nothing to bucket and no Uncategorized row appears.

**Month**:
The calendar year-and-month (e.g. `2026-03`) derived from an Expense's **Date** — the time bucket the **Report** groups spending into. A Month is a calendar span, not a rolling window or a billing cycle, and like the Date it comes from it carries no time-of-day and no timezone (see [ADR 0015](adr/0015-expense-identity-and-date-encoding.md)). A Report's columns are the Months in its selected **Report range** — by default the trailing few months, up to the whole Book. Within that range a Month with no spending still appears and reads as zero.

**Report**:
A computed, read-only summary of a Book's Expenses. For the MVP it is the total of each Category — plus the **Uncategorized** bucket when any Expense is uncategorized — broken down by **Month**, reconciling to a grand total (see [ADR 0020](adr/0020-bounded-time-series-in-review.md)). A Report derives entirely from the Expenses it summarizes: it stores nothing of its own and is recomputed on demand. It covers the Months in its **Report range**, and every total — each Category row, each Month column, and the grand total — reconciles to that range, not to the Book's lifetime.

**Report range**:
How far back a **Report** looks — the rule that fixes which Months it covers. It is a _trailing_ range measured from the current Month: the last _N_ Months (e.g. the last 6), or _all_ Months back to the Book's earliest Expense. Because every total in a Report reconciles to the range it covers (see **Report**), a shorter range re-scopes each Category's total to spending _within_ it; only the _all_ range recovers a Category's lifetime figure. Deliberately a small set of trailing presets, not an arbitrary custom start/end — bounded, in the spirit of [ADR 0020](adr/0020-bounded-time-series-in-review.md). Named _range_, not "window," because a **window** in this app is a native desktop window (see [ADR 0006](adr/0006-multi-window-desktop-shell.md)).

**Sync link**:
The connection between two LocalCents peers over which they exchange changes to reconcile a shared **Book**. The Mac side can _suspend_ the link — go offline — so the two copies accept edits independently and diverge, then _resume_ it to reconcile them. Suspending and resuming on cue is the offline-collaboration demo's control (see [ADR 0025](adr/0025-two-peer-sync-architecture.md)).

**Conflict**:
What LocalCents surfaces when two peers' independent edits to the same **Expense** cannot both stand as-is once their diverged copies reconcile over a **Sync link**. LocalCents resolves the merge but does so with notice to the user. LocalCents keeps what the losing side wrote and signals that a choice was made, so the user can review it and pick a new winner. Two kinds arise — a **Scalar conflict** and an **Edit-vs-delete conflict**. The umbrella UI label is _Synced changes_, and the copy never names Automerge, CRDTs, or "merge" — it talks only about LocalCents and the user's Expenses.

**Scalar conflict**:
The **Conflict** where the two peers concurrently wrote the same scalar field of one Expense. LocalCents keeps one value and retains the losing alternative(s) — more than two edits can collide, so it is one kept value plus _N_ alternatives, never a fixed pair — each tagged with its provenance (which device wrote it, and when). The user can _override_ to any alternative, which is a normal new edit that wins going forward, or dismiss the conflict to accept the kept value. Named _scalar_ because the field is one atomic value with no character-level merge; the code type is `field_conflict`, and the UI says only that LocalCents "kept one value," never "scalar."

**Edit-vs-delete conflict**:
The **Conflict** where one peer edited an Expense while the other deleted it. The delete wins, so the Expense is absent from the reconciled Book, but the dropped edit is surfaced rather than lost — the user is offered to _restore_ the Expense or keep it deleted. Unlike a **Scalar conflict**, no Expense survives to reconcile a value within, so the only choice is restore-or-keep-deleted.
