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

**Expense**:
A financial transaction that represents money the user has spent.

**Category**:
A classification of an Expense that answers "what kind of spending is this?" An
Expense has _at most one_ Category and may have none — quick entry never blocks on
assigning one. Because an Expense carries at most one Category, expenses can be
grouped and summed without double-counting. (A future many-per-Expense label — a
_tag_ — is a different concept and is out of scope for the MVP.)

**Uncategorized**:
Not a Category entity, but the computed bucket of Expenses that have no Category.
It always appears as a row in group-by / totals views so category totals reconcile
to the grand total, and it doubles as the worklist of Expenses that still need a
Category.
