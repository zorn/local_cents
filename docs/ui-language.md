# UI Language

We want to take care when presenting terminology inside the user interface. We want to choose our terms with intent and consistency.

## Creating things

Following a macOS norm, we use the term **"New"** when initiating a blank top-level entity from a main menu or a button (e.g., "New Book", "New Expense"). If the creation process requires a form, we then use the term **Create** for a submit-like button label as it is an appropriate and user friendly action verb.

If you are appending a sub-item to an existing entity — for example a Tag or an Attachment (both deferred past the MVP; see [ADR 0008](adr/0008-mvp-expense-shape.md)) — you can use the verb **Add** (e.g., "Add Tag", "Add Attachment"). These sub-items are part of the identity of the parent Expense, so if you add a new one then the Expense is considered updated.

## Editing things

Use **"Edit"** to label the action of opening an entity for modification. 

## Deleting things

Use **"Delete"** for permanent removal of an entity. Use **"Remove"** only when detaching an item from another entity without destroying it (e.g., removing a Category from an Expense — the Category itself still exists, only the association is cleared).

## Acting on things

Use **"Open"** when referencing the action of opening a Book in its document window.

## Confirming destructive actions

When a destructive action needs a confirmation dialog, follow Apple's long-standing
alert guidance (unchanged from the 1992 *Macintosh Human Interface Guidelines*
through the current HIG; see
[research note](research/apple-hig-destructive-confirmation-alerts.md)):

- **Title the buttons with verbs that name the result** — never "OK"/"Yes"/"No".
  A delete confirmation uses **Cancel** and **Delete**, not "OK"/"Cancel".
- **The destructive button is styled destructive (red) and is _not_ the default.**
  The safe choice — **Cancel** — is the default/Escape action, so an absent-minded
  Return or Escape cancels rather than destroys.
- **Make the title specific** — a complete question naming the thing, e.g. *"Delete
  the "Groceries" category?"* — and **state the consequence in the body** (e.g.
  that affected expenses become Uncategorized).
