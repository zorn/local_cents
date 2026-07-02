# Categories Not Tags

## Problem Statement

A core MVP goal is to **group expenses and total each group** ("how much did we
spend on groceries?"). Our early mockups and sample data leaned on **tags** — a
many-per-expense label. But tags are additive and overlapping: an expense tagged
both `household` and `clothing` gets counted under *both* groups, so the sum of
the per-group totals exceeds the actual amount spent. Tags cannot produce an
honest group-by total.

We also need to reconcile this with quick entry, where expenses are deliberately
allowed to be saved incomplete (e.g. `dentist` with no cost), which means many
expenses will arrive with no classification at all.

## Decision

For the MVP we classify expenses with **Categories, not Tags**. The model:

- **At most one Category per Expense.** Because an expense belongs to a single
  Category, per-category totals sum to the grand total without double-counting.
  This single-valued partition is the whole reason we chose categories over tags.
- **Category is optional.** An Expense may have no Category. Quick entry never
  blocks on assigning one — saving is always allowed.
- **"Uncategorized" is a computed absence, not an entity.** Expenses with no
  Category are rendered together under an "Uncategorized" bucket in group-by /
  totals views, so category totals still reconcile to the grand total. That same
  bucket is the worklist of expenses that still need a Category. There is no
  "Uncategorized" record; users cannot rename, delete, or assign to it.
- **No seeded categories.** A new Book starts with an empty category list so the
  user builds a taxonomy meaningful to them, rather than being anchored by our
  defaults. Suggested categories live in help docs, not shipped data.
- **Categories are a curated "hard list" managed in a dedicated view.** Creating
  or editing a Category is a deliberate act performed in its own management place.
  The expense editor only *selects* from existing categories — there is no
  create-a-category-on-a-whim inline in the expense pane.
- **Deleting a Category un-files its Expenses.** Categories can be deleted freely;
  any Expense using a deleted Category becomes Uncategorized from that point on
  (its reference is nulled — Expenses reference a Category by a stable id, so a
  rename never touches them). The management view shows a **count of Expenses per
  Category**, and deletion prompts a confirmation that explains those Expenses will
  become Uncategorized.

The intended rhythm that falls out of these rules: **capture fast, leave
uncategorized when no fitting Category exists, then later curate categories in the
management view and work the Uncategorized pile.** That friction is by design.

**Tags are deferred, possibly indefinitely.** They are a genuinely different
concept (a zero-or-many label answering "what else is true about this?") and may
return once categorization and totals are solid — but they are out of scope for
the MVP.

This **amends ADR 0002 (Expense Attributes)**, which listed Tags as a phase-one
attribute "for categorization and filtering." Categorization is now handled by
Category; the Tags attribute is deferred.

## Consequences & Tradeoffs

- **What we accept:** an expense that "feels like two things" (e.g. a Target run
  that is both `household` and `clothing`) must be filed under a single Category.
  The richer multi-label view is postponed with Tags.
- **What we accept:** a brand-new user sees an empty category list and some
  mid-entry friction when a needed Category does not yet exist — they save
  uncategorized and curate later. We consider this a feature (deliberate
  taxonomy), not a gap.
- **What gets easier:** group-by totals are arithmetically honest by
  construction, and "expenses needing attention" is a free by-product of the
  Uncategorized bucket rather than a separate flag to maintain.
- **What we avoid:** a system-vs-user category distinction (from seeding) and a
  magic "Uncategorized" record, both of which would spawn their own
  rename/delete/default-assignment edge cases.
- **Deferred:** bulk-reassigning Expenses from one Category to another (and merging
  categories) is a recognized future convenience — captured now, not built for the
  MVP. Until then, re-filing happens one Expense at a time via the Uncategorized
  worklist.
