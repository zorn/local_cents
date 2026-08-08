# Automerge Edit-vs-Delete: What Happens and What We Can Detect

> Research note feeding [issue #213](https://github.com/zorn/local_cents/issues/213) — "when one actor edits an expense and another concurrently deletes it, what does Automerge do, and what is left for us to detect and present?"
> Every claim below links to a primary source: the official docs at [automerge.org](https://automerge.org/), the `automerge` / `autosurgeon` crates on docs.rs pinned to the versions we build against, and our own source files. No blog posts or secondary write-ups were used.
> This extends the conflict-representation note ([issue #211](https://github.com/zorn/local_cents/issues/211), `docs/research/automerge-conflict-representation.md`) — read that first for the conflict model, winner selection by op id, and the `get` vs `get_all` surface. This note does not repeat it.
>
> **Placement:** saved to `docs/research/` to match the on-disk convention. That home is unsettled — [issue #209](https://github.com/zorn/local_cents/issues/209) is still deciding where research notes live and [#208](https://github.com/zorn/local_cents/pull/208) already stopped rendering them — so treat the path as provisional.

## TL;DR

For our modeling — expenses are a `Vec<Expense>`, i.e. an Automerge **list of map objects** keyed by `id` — a concurrent "edit one field of expense X" versus "delete expense X" resolves as **delete wins**. The expense disappears from the merged list; the edit does **not** resurrect it. This is *not* the "update wins over delete" resurrection you would get from Automerge's list rule, because that rule is about replacing a list element's value, whereas our edit is a `put` on a key *inside* the referenced object — a different operation that does not contest the list-element deletion.

The dropped edit is not a losing-scalar register (the #211 shape). It survives as a whole **orphaned object**: the expense's object still exists in the document's op set with the new field value, but it is unreachable from the expenses list. Our `decode/1` (autosurgeon `hydrate`) traverses from the root, never reaches the orphan, and so returns the list *without* the expense and with *no signal* that it was edited elsewhere. Detecting "edited elsewhere but deleted here" is therefore impossible on the current path and needs a new read seam in the Rust NIF.

## 1. Who wins — delete wins, no resurrection (the list-vs-map subtlety)

**Our shape is a list of objects.** `native/ex_automerge/src/lib.rs:65-70` models the document as `expenses: Vec<Expense>`, and each `Expense` (`lib.rs:36-44`) is a struct with `#[key] id`. autosurgeon reconciles a `Vec` to an **Automerge list** (`ObjType::List`), and `#[key]` only changes how elements are *matched* across changes — by identity, not position — it does not turn the list into a map ([autosurgeon crate root, docs.rs 0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/): a `Vec<T>` becomes a list; `#[key]` lets autosurgeon "recognize elements by their key value" so it can tell "inserted at the front" from "updated the first item"). The moduledoc at `lib.rs:20-33` states the same intent.

**What operations the two sides actually emit.** Both sides go through `reconcile/3` (`lib.rs:156-167`), which loads the prior document and lets `autosurgeon::reconcile` diff the hydrated state against the new state and emit the minimal ops.

- **Edit side.** The device loaded a document where expense X still exists, and its new state still contains X with one field changed. autosurgeon matches X by `#[key]` and does an **in-place update** of that field — a `put` on the expense object's map key — not a re-insert ([autosurgeon crate root, docs.rs 0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/): "when a field changes in a matched element, reconcile updates that specific field on the object rather than replacing the entire element").
- **Delete side.** The new state omits X. autosurgeon matches by `#[key]`, finds X present in the doc but absent in the new state, and **deletes the list element** ([autosurgeon crate root, docs.rs 0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/): "when an element with a given key is absent in the new value, the corresponding list element is deleted").

**Why the delete wins here (and why the resurrection rule does not fire).** Automerge's list merge rules are, verbatim ([Merge Rules, automerge.org](https://automerge.org/docs/reference/under-the-hood/merge-rules/)):

> "If `A` deletes element at index `i` and `B` updates the element at `i` then set the value of `i` to the updated value from `B`"

That rule — the "update wins / resurrection" case — fires only when `B` **assigns a new value to the list element itself** (replacing what the element holds at position `i`). Our edit side does not do that. It emits a `put` targeting a key *inside* the expense object; it never re-assigns the list element. So the list-element deletion is **uncontested**, and the sibling list rule applies instead: a deleted element with no competing element-value op is removed. The map delete-vs-update rule ("If `A` deletes key `x` and `B` sets `x` to a new value then set the value to `B`'s", [Merge Rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/)) also does not save the expense: that rule is about a *map key* being deleted, whereas here the whole object was removed as a *list element*, and the concurrent `put` was on a key one level *deeper* than the deletion.

**So it depends entirely on list-element vs map-key deletion semantics** — the axis the ticket asked about:

| Scenario | Delete target | Concurrent op | Outcome |
|---|---|---|---|
| Our expense edit-vs-delete | list element (the whole expense object) | `put` on a key *inside* that object | **delete wins; object orphaned** |
| Replace element value | list element at index `i` | assign a new value to element `i` | update wins (list rule #2, resurrection) |
| Field-level, if expenses were a map keyed by id | map key `x` (the expense) | `put` on that same key `x` | update wins (map rule #3) |

The second and third rows are the documented "update wins" cases; our actual encoding is the first row.

## 2. What trace remains — an orphaned object, not a losing register

The dropped edit is **not** discarded, but its shape differs from the #211 losing-scalar register. In #211 the trace was a second value on a *live, reachable* key, readable via `get_all`. Here the trace is a whole **object that is no longer reachable from the list**:

- Automerge never garbage-collects objects; a deleted list element leaves a tombstone and the element is "removed from the element relation but remains in the list as a tombstone," and "from a user's point of view a list element only exists if it has at least one associated value" ([Merge Rules, automerge.org](https://automerge.org/docs/reference/under-the-hood/merge-rules/); the OpSets model, [Kleppmann et al., arXiv:1805.04263](https://arxiv.org/pdf/1805.04263)). The expense object's own ops — including the concurrent field `put` — remain valid ops against that object's `ObjId`; they simply describe an object that the live list no longer points at.
- **Reading it via the Rust crate.** You cannot reach the orphan by normal traversal (root → `expenses` list → element), because the element is gone. You need the object's `ObjId` first. Given an `ObjId`, `ReadDoc::get_all(obj, "description")` / `get(obj, "description")` read its keys regardless of list membership ([docs.rs/automerge/0.10.0 ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)). To *find* the `ObjId`, the crate offers `ReadDoc::iter()`, which returns a `DocIter` that "iterate[s] over all the objects in the document ... in causal order" yielding `(object ID, property)` pairs ([docs.rs/automerge/0.10.0 ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)), and change-history inspection via `get_changes()` on the `Automerge` type ([docs.rs/automerge/0.10.0 Automerge](https://docs.rs/automerge/0.10.0/automerge/struct.Automerge.html)). **Caveat:** the 0.10.0 docs do not state whether `iter()` includes objects orphaned from the tree, and there is no documented API to test reachability or to enumerate only orphaned/deleted objects ([docs.rs/automerge/0.10.0 ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)). Confirming what `iter()` yields for an orphan would require a spike against the pinned crate — flagged, not built.

So: the edit is recoverable in principle from the merged bytes, but as an unreachable object reached by a different mechanism than #211's `get_all`-on-a-live-key.

## 3. Detectability from Elixir — not today; the seam

**Not on the current path.** `decode/1` calls `autosurgeon::hydrate` (`lib.rs:130-134`), which traverses from the root through the `expenses` list. A deleted list element yields no value and is skipped; the orphaned object is not referenced by the list, so hydrate never visits it. The resulting `BookDoc` (`lib.rs:65-70`) → Elixir map (`lib/local_cents/tracking/ex_automerge.ex`) → `BookDocument` (`lib/local_cents/tracking/book_document.ex`) simply lacks the expense. There is **no slot** anywhere for "this was edited elsewhere before it was deleted," and nothing in the winner-only pipeline could surface it. From Elixir the merge looks identical to an ordinary uncontested delete.

**The seam (noted only — not built, per the ticket).** Detection needs a **new parallel read path in `native/ex_automerge/src/lib.rs`**, additive to `hydrate`/`decode`, exactly as #211 concluded for conflicts — the two features share the same boundary problem. Two viable shapes, in rough order of confidence:

1. **Merge-time diff (most robust, no orphan-reachability assumption).** `merge/2` (`lib.rs:169-179`) holds both pre-merge documents. Before merging, hydrate each side's expense-id set; after merging, hydrate the result. An id that was *present (and whose fields differ) on one side* but *absent from the merged result* is an "edited-elsewhere-but-deleted-here" case. This avoids depending on whether `iter()` can reach the orphan. It requires `merge/2` to return structured metadata alongside the merged bytes rather than bytes only.
2. **Post-merge orphan scan.** A new NIF (e.g. `dropped_edits/1`) walks the merged document with `iter()` and/or `get_changes()`, finds expense-shaped objects not present in the live `expenses` list, reads their fields via `get_all`, and returns them across Rustler as an extra structure. This depends on the unconfirmed `iter()`-includes-orphans behavior from section 2.

Either way the Elixir shapes (`ExAutomerge.state` / `raw_expense`, `BookDocument`) would gain a place to carry the dropped-edit records. **Noted only — nothing built or edited here.**

## 4. Version caveat

- **Crate pin confirmed.** `native/ex_automerge/Cargo.toml:12` pins `automerge = "=0.10.0"` (exact), with `autosurgeon = "0.12"`. All docs.rs citations above are for those exact versions.
- **The merge rules are algorithm-level, not version-level.** The delete-vs-update rules quoted in section 1 describe Automerge's merge algorithm ([Merge Rules, automerge.org](https://automerge.org/docs/reference/under-the-hood/merge-rules/)) and are a property of the shared Automerge core that both the Rust crate and the current JS package are built on; they are not expected to differ JS-vs-Rust or across the Automerge 2.x / Rust 0.x line. The formal basis is the OpSets model ([arXiv:1805.04263](https://arxiv.org/pdf/1805.04263)).
- **API names are Rust-crate-specific and pinned.** `get` / `get_all` / `iter` / `parents` on `ReadDoc` and `get_changes` on `Automerge` are 0.10.0 surface ([ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html), [Automerge](https://docs.rs/automerge/0.10.0/automerge/struct.Automerge.html)); the JS analogue for reading alternatives is `getConflicts` (see #211). Whether `iter()` yields orphaned objects is unverified for 0.10.0 (section 2) and is the one point that should be spiked before relying on seam option 2.
- **autosurgeon behavior is 0.12-specific.** The in-place-put-on-edit and delete-list-element-on-removal behavior of `#[key]` is documented for 0.12 ([autosurgeon crate root, docs.rs 0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/)); a future autosurgeon bump should re-confirm it.

## Sources

- Merge rules (delete-vs-update, list vs map, tombstones) — [automerge.org/docs/reference/under-the-hood/merge-rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/)
- Formal model (OpSets, object persistence) — [Kleppmann et al., arXiv:1805.04263](https://arxiv.org/pdf/1805.04263)
- `get` / `get_all` / `iter` / `parents` — [docs.rs/automerge/0.10.0 ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)
- `get_changes`, `iter` — [docs.rs/automerge/0.10.0 Automerge](https://docs.rs/automerge/0.10.0/automerge/struct.Automerge.html)
- `Vec` → list, `#[key]` matching, in-place put on edit, delete on removal — [docs.rs/autosurgeon/0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/)
- Crate versions — `native/ex_automerge/Cargo.toml`
- Our bridge — `native/ex_automerge/src/lib.rs`, `lib/local_cents/tracking/ex_automerge.ex`, `lib/local_cents/tracking/book_document.ex`
- Prior conflict-representation research — `docs/research/automerge-conflict-representation.md` ([issue #211](https://github.com/zorn/local_cents/issues/211))
