# Category Assignment Through the Expense Editor

## Problem Statement

[ADR 0005](0005-categories-not-tags.md) established that the expense editor only
*selects* an existing Category — never creates one — and the Category domain model
([issue #65](https://github.com/zorn/local_cents/issues/65)) implemented assignment
as **standalone `assign_category`/`unassign_category` commands**, deliberately kept
out of `Expense.changeset/3`. That changeset moduledoc still reads: `category_id`
"is **not** a `changeset/3` field … assignment is a deliberate act done through
separate `BookDocument` commands." That shape was correct while nothing in the UI
assigned a Category.

[Issue #67](https://github.com/zorn/local_cents/issues/67) adds a Category picker
to the full editor, and that forces a question the earlier tickets left open: **when
the user picks a Category in the editor form and presses Save, how does the
assignment persist?** The editor is a single form with one Save/Create button and a
"nothing commits until Save; close discards" contract. Routing the picker through
the standalone `assign_category` command would break that contract two ways: it
can't run in the *new*-expense flow (no expense id exists until `add_expense`
returns), and firing it the moment the user picks would persist a change the user
could still cancel. Doing `add_expense` then `assign_category` as two sequential
writes reintroduces a partial-failure window and a two-broadcast "uncategorized then
categorized" flicker.

## Decision Made

**Category assignment for the editor flows through the same command as the text
Save, atomically.** Concretely:

- `Expense.changeset/3` now **casts `category_id`** as an ordinary field. A
  `<select>` over existing Categories is a *controlled reference*, not the
  free-form text the old moduledoc note was guarding against, so it belongs on the
  form like `date`/`description`/`cost`. The existing `normalize`/`blank_to_nil`
  turns a blank selection into `nil` = Uncategorized for free.
- `add_expense`/`edit_expense` **keep their arity** — `category_id` rides in the
  `attrs` map. `edit_expense` becomes a true full-replace *including* Category
  (a blank selection unassigns). The **context/core validates the id belongs to the
  Book**, returning `{:error, :category_not_found}`, because the changeset cannot
  see the Book's Category list.
- The standalone `assign_category`/`unassign_category` commands **remain** — the
  category management view and any future live-assign UI use them. The editor
  simply no longer routes through them.
- Category commands emit a new **coarse, additive `{:categories_updated, book_id}`**
  broadcast alongside the existing `{:book_updated, …}`. The editor's Category cache
  refreshes only on `:categories_updated`, so ordinary expense edits never churn it.

This **refines ADR 0005** ("the editor only selects") with the mechanism: selection
is a field on the expense form, committed by the same Save, not a separate deliberate
command. ADR 0005's guarantees are untouched — no inline creation, at most one
Category per Expense, blank = Uncategorized.

## Consequences & Tradeoffs

* **Considered:** keeping the standalone commands as the only assignment path and
  having the editor call `add_expense` then `assign_category` (two writes).
  Rejected — no id exists for the *new*-expense case at pick time, and the two-write
  sequence adds a partial-failure window and a double-broadcast flicker that a single
  atomic command avoids.
* **Considered:** firing `assign_category` immediately when the user picks, with Save
  governing only the text fields. Rejected — it breaks the editor's "nothing commits
  until Save" contract and still can't serve the new-expense flow.
* **Accepted:** `category_id` now lives on `Expense.changeset/3` *and* the standalone
  `assign_category`/`unassign_category` commands still exist. Two ways to set the same
  field looks redundant until you see they serve different surfaces — the editor's
  form vs. direct assignment. The Expense moduledoc is updated to explain both.
* **Accepted:** the new `:categories_updated` signal is additive, so category commands
  now emit two messages. Every subscriber to a Book's topic therefore receives it —
  the library and category-management views already reload on the `:book_updated` that
  still fires, so each simply ignores `:categories_updated` with a no-op clause rather
  than reloading twice. The cost is one extra broadcast per category change, which is
  rare.
* **Easier:** the picker cache in `BookLive` reacts to a Category-shaped signal
  instead of every expense-level `:book_updated`, so typing in the editor doesn't
  rebuild the option list.
