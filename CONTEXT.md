# LocalCents

The domain glossary for LocalCents — the canonical vocabulary for the app's core
concepts. Keep this file to domain nouns only: UI verbs live in
[UI Language](docs/ui-language.md), and general software / DDD modeling terms live
in [Software Terms](docs/software-terms.md).

## Language

### Tracking (Bounded Context)

**Book**:
The document that all other main domain entities live inside. As the app is
starting out we are recording expenses only for the most part, but in time we
hope to expand towards income and other financial data.

**Last Updated**:
When a Book was last changed — the time of the most recent edit at its Automerge
document's heads, not the moment its file was last written locally. Derived from
change history so it survives sync: after a merge it reflects the latest edit
across the merged copies rather than the latest local write. Because change times
come from the writing device's clock, it is a best-effort, advisory value, not an
authoritative ordering (see
[ADR 0012](docs/adr/0012-book-last-updated-timestamp.md)).

**Expense**:
A financial transaction that represents money the user has spent. Its **Cost**,
when recorded, is non-negative — the MVP tracks spending only, so refunds, credits,
and income are out of scope. A missing Cost is left _absent_ rather than recorded as
zero, so totals stay honest and a genuine zero-Cost Expense is distinct from one
whose amount simply has not been entered yet (see
[ADR 0008](docs/adr/0008-mvp-expense-shape.md)).

**Category**:
A classification of an Expense that answers "what kind of spending is this?" An
Expense has _at most one_ Category and may have none — quick entry never blocks on
assigning one. Because an Expense carries at most one Category, expenses can be
grouped and summed without double-counting. (A future many-per-Expense label — a
_tag_ — is a different concept and is out of scope for the MVP.)

**Uncategorized**:
Not a Category entity, but the computed bucket of Expenses that have no Category.
It appears as a row in group-by / totals views whenever any Expense is
uncategorized, so category totals reconcile to the grand total, and it doubles as
the worklist of Expenses that still need a Category. When every Expense is filed,
there is nothing to bucket and no Uncategorized row appears.

**Month**:
The calendar year-and-month (e.g. `2026-03`) derived from an Expense's **Date** —
the time bucket the **Report** groups spending into. A Month is a calendar span,
not a rolling window or a billing cycle, and like the Date it comes from it carries
no time-of-day and no timezone (see
[ADR 0015](docs/adr/0015-expense-identity-and-date-encoding.md)). A Report spans
every Month from the earliest to the latest Expense in the Book, so a Month with no
spending still appears and reads as zero.

**Report**:
A computed, read-only summary of a Book's Expenses. For the MVP it is the total of
each Category — plus the **Uncategorized** bucket when any Expense is
uncategorized — broken down by **Month**, reconciling to a grand total (see
[ADR 0020](docs/adr/0020-bounded-time-series-in-review.md)). A Report derives
entirely from the Expenses it summarizes: it stores nothing of its own and is
recomputed on demand.
