# Automerge Conflict Representation and How It Reaches Elixir

> Research note feeding [issue #211](https://github.com/zorn/local_cents/issues/211) — "what does Automerge represent when two changes to the same value conflict, and how does that representation reach us through the Rust `automerge` crate we bind via Rustler?"
> Every claim below links to a primary source: the official docs at [automerge.org](https://automerge.org/), the `automerge` / `autosurgeon` crates on docs.rs pinned to the exact versions we build against, the Automerge GitHub repo, and our own source files. No blog posts or secondary write-ups were used.
>
> **Placement:** saved to `docs/research/` to match the existing research-note convention on disk. That home is unsettled — [issue #209](https://github.com/zorn/local_cents/issues/209) is still deciding where research notes live and [#208](https://github.com/zorn/local_cents/pull/208) already stopped rendering them — so treat the path as provisional.

## TL;DR

For a genuine conflict — two devices concurrently writing the same map key — Automerge keeps **a multi-value register**: it deterministically picks one winner (by operation id) that reads out normally, and it retains the losing values alongside, each tagged by the id of the operation that wrote it. In the Rust `automerge` crate that register is read with **`get_all`** (returns every `(Value, ExId)` pair) versus **`get`** (returns one arbitrarily chosen winner). Text and list edits do **not** conflict — they merge element-by-element.

The catch for us: this representation **never reaches Elixir today**. Our bridge hydrates the document through autosurgeon into a plain struct, which reads only the winner (the `get` path). The alternatives exist in the merged document bytes but are discarded at the NIF boundary. And our expense `description` is a plain Rust `String`, i.e. an Automerge **scalar** — so concurrent description edits are a last-writer-wins conflict (one wins by op id, the other becomes a retained loser), **not** a character-level text merge.

## 1. The conflict model — what conflicts, what doesn't, and who wins

**What counts as a conflict.** Only one situation: *"when users concurrently update the same property in the same object"* — [Conflicts, automerge.org](https://automerge.org/docs/reference/documents/conflicts/). A map key set on both sides concurrently is the conflict case.

**What does not conflict.** List/sequence and text edits never collide. The merge rules state: for concurrent inserts after the same index, Automerge will *"arbitrarily choose one to insert first and then insert the other immediately afterwards"*, and *"The characters of a text object are merged using the same logic as lists"* — [Merge Rules, automerge.org](https://automerge.org/docs/reference/under-the-hood/merge-rules/). Both concurrent inserts survive; there is no winner/loser, so there is nothing to surface.

**How the winner is chosen (deterministic tie-break).** For concurrent puts to the same key Automerge will *"randomly choose one value"* but in a way all nodes agree on — [Merge Rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/). The rule is by operation id, not wall-clock time: *"Conflicts are ordered based on the counter first (using the actorId only to break ties when operations have the same counter value)"* — [Conflicts](https://automerge.org/docs/reference/documents/conflicts/). An operation id is a `(counter, actorId)` pair; highest counter wins, actorId breaks ties. The counter is a **Lamport logical clock**, not a timestamp: each actor increments its own counter per operation and fast-forwards it past any counter it merges in, so it tracks *causal* order, not real-world time. For two genuinely concurrent edits — neither side having seen the other, i.e. the offline case — the counters are typically equal, so the winner falls to the `actorId` tie-break, which is **effectively arbitrary** (a comparison of random per-actor ids). The edit that happens last in wall-clock time has no advantage. (This matches the finding in [`automerge-last-updated.md`](automerge-last-updated.md) section 4: the winner of a scalar register is chosen by op id, not by any timestamp value.)

## 2. The alternatives metadata (the JS `getConflicts` equivalent)

When a key conflicts, Automerge keeps a **multi-value register**: the winner plus every loser.

- *"Although only the winning value appears in the document itself, Automerge preserves all conflicting values"*, retrievable via `getConflicts()`, which returns *"the conflicting values, both the 'winner' and any 'losers'."* — [Conflicts](https://automerge.org/docs/reference/documents/conflicts/).
- **Keying:** *"The keys in the conflicts object are the internal IDs of the operations that updated the property."* — [Conflicts](https://automerge.org/docs/reference/documents/conflicts/). So the alternatives are keyed by operation id (`actor@counter`), not by device name or timestamp.
- **Lifetime — this is the important subtlety.** The conflicts object is **not a permanently stored field**. It reflects the state of the merged document as it currently stands, and it clears itself on the next write: *"the next time you assign to a conflicting property, the conflict is automatically considered to be resolved, and the conflict disappears"* — [Conflicts](https://automerge.org/docs/reference/documents/conflicts/). It is not "only observable at merge time" in a fleeting sense — it persists as long as the conflicting register is unresolved, because the losing operations remain in the document's op set — but it is derived from those ops on read, and any subsequent assignment to that key collapses it back to a single value.

## 3. The Rust `automerge` crate surface that exposes conflicts

**Version confirmation.** `native/ex_automerge/Cargo.toml:12` pins `automerge = "=0.10.0"` (exact-version pin), with `autosurgeon = "0.12"` and `rustler = "0.38.0"`. All docs.rs citations below are for those exact versions.

Conflicts are read through the `ReadDoc` trait ([docs.rs, automerge 0.10.0](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)):

- **`get`** — returns `Result<Option<(Value<'_>, ExId)>, AutomergeError>`. Docs: *"In the case of a key which has conflicting values, this method will return a single arbitrarily chosen value."* This is the winner-only path.
- **`get_all`** — returns `Result<Vec<(Value<'_>, ExId)>, AutomergeError>`. Docs: *"If there are multiple conflicting values for a given key this method will return all of them, with each value tagged by the ID of the operation which created it."* This is the `getConflicts` equivalent.
- `get_at` / `get_all_at` are the same two, evaluated at a specific set of `heads` (a historical point) rather than the current frontier.

So each returned pair is `(Value, ExId)`: `Value` is the scalar/object value, and `ExId` (the exported object/op id) is the tag identifying which operation wrote it — the Rust analogue of the op-id keys in JS `getConflicts`. To enumerate a conflicted value's candidates from merged bytes: get the containing object's `ObjId`, then call `get_all(obj, "description")` and read the `Vec`.

## 4. Our current bridge — how values are modeled, and the seam that would have to change

**Today's model (winner-only, conflicts discarded at the NIF boundary).**

- The Rust NIF represents an expense as a flat struct of single scalar fields — `native/ex_automerge/src/lib.rs:36-44`:
  ```rust
  #[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
  pub struct Expense {
      #[key] pub id: String,
      pub date: String,
      pub description: String,
      pub cost: Option<String>,
      pub category_id: Option<String>,
  }
  ```
- `decode/1` calls `autosurgeon::hydrate` into `BookDoc` (`lib.rs:138-143`). autosurgeon's `Hydrate` reads each field as **one value** — the winner — the equivalent of the `get` path, never `get_all`. Losing alternatives are never materialized.
- `NifMap` then turns that struct into an Elixir map of single scalar keys. On the Elixir side `ExAutomerge.state`/`raw_expense` (`lib/local_cents/tracking/ex_automerge.ex:70-93`) and `BookDocument`'s `Expense` (`lib/local_cents/tracking/book_document.ex:358-372`) both carry `description` as one `String.t()`. There is no slot anywhere in the pipeline for "the other value."
- `merge/2` (`lib.rs:169-179`) is `left.merge(&mut right)` — it produces the merged document bytes that *contain* the multi-value register, but the very next `decode` collapses it to the winner. So the conflict data is created by `merge` and immediately dropped by `decode`.
- `reconcile/3` (`lib.rs:156-167`) writes the new state via `autosurgeon::reconcile`, which diffs the hydrated state against `new_state` and emits only the minimal ops for what changed (`lib.rs:152`). So a reconcile after a merge *resolves* (collapses) a conflict only on the keys whose value it actually rewrites — an unchanged key gets no new op and keeps its multi-value register. Where it does write, it clears the conflict, matching the "next assignment clears the conflict" rule from section 2.

**The seam.** Carrying conflict info into Elixir is a **new parallel read path**, not a change to `reconcile`/`merge`. autosurgeon's `hydrate` is a winner-only lens by design and cannot express alternatives, so the change lives at the NIF boundary in `native/ex_automerge/src/lib.rs`: a new NIF (e.g. `conflicts/1` or an enriched `decode`) would walk the document with the core `automerge` `ReadDoc` API — for each expense `ObjId`, call `get_all(obj, "description")` (and any other scalar field we care about) — and return the `Vec<(Value, ExId)>` across Rustler as an extra structure (op-id-keyed alternatives) that Elixir's `state`/`raw_expense` shapes would be extended to hold. autosurgeon stays available on the same `AutoCommit` handle (per [`automerge-last-updated.md`](automerge-last-updated.md) section 3), so this is additive: keep hydrate for the normal decode, drop to core `get_all` for the conflict enumeration. **Noted only — nothing built or edited here per the ticket.**

## 5. The expense `description` field specifically — scalar, so it conflicts (no character merge)

**`description` is an Automerge scalar, not a text object.** In `native/ex_automerge/src/lib.rs:41` the field is a plain Rust `String`. autosurgeon reconciles a `String` as a scalar string value; character-level text merging requires the distinct `autosurgeon::Text` type, which the docs describe as reconciling *"to an `automerge::ObjType::Text`"* and existing specifically for collaborative character-level edits via `splice()`/`update()` — [autosurgeon::Text, docs.rs 0.12.0](https://docs.rs/autosurgeon/0.12.0/autosurgeon/struct.Text.html). A plain `String` reconciles as a scalar, so *"the entire string is treated as an atomic unit"* and *"concurrent edits would result in last-write-wins semantics rather than character-level merging"* (autosurgeon docs, [crate root](https://docs.rs/autosurgeon/0.12.0/autosurgeon/): the crate provides `Text` as a separate data type precisely for text). We do **not** use `autosurgeon::Text` anywhere.

**Merge outcome for our encoding.** If two devices concurrently edit the same expense's `description`:

1. The register conflicts (section 1) — it is a scalar map key written on both sides.
2. Automerge deterministically picks one winner by operation id (section 1) and retains the other as a loser in the multi-value register (section 2).
3. `get_all` in the core crate could enumerate both candidates (section 3), but our `decode`/`hydrate` path reads only the winner and discards the loser (section 4).

So today the demo's concurrent description edit produces a **silent last-writer-wins by op id** — one edit's text appears, the other is dropped from view (though still recoverable from the bytes via a future `get_all` NIF). It is **not** a character-by-character merge; that would only happen if `description` were retyped to `autosurgeon::Text`, which is a separate schema decision with its own migration cost.

## Sources

- Conflict model, winner selection, alternatives, lifetime — [automerge.org/docs/reference/documents/conflicts](https://automerge.org/docs/reference/documents/conflicts/)
- Map/list/text merge rules — [automerge.org/docs/reference/under-the-hood/merge-rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/)
- `get` vs `get_all`, `Value`/`ExId` — [docs.rs/automerge/0.10.0 ReadDoc](https://docs.rs/automerge/0.10.0/automerge/trait.ReadDoc.html)
- `String` scalar vs `Text` object — [docs.rs/autosurgeon/0.12.0 Text](https://docs.rs/autosurgeon/0.12.0/autosurgeon/struct.Text.html), [crate root](https://docs.rs/autosurgeon/0.12.0/autosurgeon/)
- Crate versions — `native/ex_automerge/Cargo.toml`
- Our bridge — `native/ex_automerge/src/lib.rs`, `lib/local_cents/tracking/ex_automerge.ex`, `lib/local_cents/tracking/book_document.ex`
- Library-choice context — [ADR 0001](../adr/0001-which-automerge-rust-library.md); related timestamp/conflict reasoning — [`automerge-last-updated.md`](automerge-last-updated.md)
