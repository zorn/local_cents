# Automerge "Last Updated" for the Library Subtitle

> Research note feeding [issue #90](https://github.com/zorn/local_cents/issues/90) — "give Books an updated_at for the library subtitle."
> Every non-obvious claim below is linked to a primary source: the official docs at [automerge.org](https://automerge.org/), the `automerge` Rust crate, the `autosurgeon` crate, and the Automerge JS API docs. No blog posts or secondary write-ups were used.

## Problem framing

We want to show a "Last Updated" timestamp per Book in the library UI. Each Book is a standard Automerge binary document stored in a `.lcbook` file. In [issue #61](https://github.com/zorn/local_cents/issues/61) we decided **not** to use the file's mtime, because file mtime is fragile once sync starts rewriting files, and after a merge we want the timestamp to reflect the *latest edit*, not the *latest local write*. Real multi-device Automerge sync/merge is planned soon, so the design must not assume a local filesystem.

This note answers: does Automerge record a per-change timestamp, how would we derive a sync-safe "last updated" from it, what does autosurgeon expose, and how does that compare to storing our own `updated_at` field inside the document.

## 1. Automerge records a per-change timestamp (`time`)

Yes. Every Automerge change carries a `time` field.

- In the Rust crate, `Change` exposes `pub fn timestamp(&self) -> i64` — [`automerge::Change`](https://docs.rs/automerge/latest/automerge/struct.Change.html).
- The value is set through `CommitOptions`. Its builder documents the unit and semantics explicitly: `with_time(self, time: i64)` / `set_time(&mut self, time: i64)`, described as *"the unix timestamp (in seconds) of the commit (**purely advisory, not used in conflict resolution**)."* — [`automerge::transaction::CommitOptions`](https://docs.rs/automerge/latest/automerge/transaction/struct.CommitOptions.html).

**Type / unit / semantics (Rust core, the canonical layer we call via Rustler):**
- Type: `i64`.
- Unit: **unix timestamp in seconds**.
- Semantics: advisory metadata only. It is **not** used in conflict resolution (see §4).

**Is it set automatically?** In the Rust core, **no — it is not injected automatically.** `CommitOptions::default()` leaves `time` as `None`, and a transaction initializes `time: 0` and only overwrites it if a time is supplied (`if let Some(t) = time { self.time = t; }`), storing `timestamp: self.time` on the change metadata — [`rust/automerge/src/transaction/inner.rs`](https://github.com/automerge/automerge/blob/main/rust/automerge/src/transaction/inner.rs). The crate docs' own example shows the caller computing the time manually: `SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs()` (note `.as_secs()` — seconds) and passing it via `CommitOptions` — [`CommitOptions` docs](https://docs.rs/automerge/latest/automerge/transaction/struct.CommitOptions.html). The WASM binding likewise only sets time when the JS caller provides one; it does not inject a default itself — [`rust/automerge-wasm/src/lib.rs`](https://github.com/automerge/automerge/blob/main/rust/automerge-wasm/src/lib.rs).

**Where automatic time-setting *does* happen: the JS wrapper.** The JavaScript `change()` API injects the current time by default. This is documented via a known bug, [automerge/automerge#965 "JS time is 1000x smaller than expected"](https://github.com/automerge/automerge/issues/965): the JS `change()` function auto-supplies `Date.now()` when no time is given, and because `Date.now()` is in **milliseconds** while the core stores **seconds**, JS-written change times are stored at 1000x the documented resolution and don't round-trip through `new Date(change.time)`. Maintainers confirm in that thread that the Rust/core canonical unit is **seconds**. **Implication for us:** if `.lcbook` documents were ever written by the Automerge JS stack, their change times could be inconsistent with Rust-written ones. Since LocalCents writes exclusively through the Rust crate (via autosurgeon + Rustler, [ADR 0001](../adr/0001-which-automerge-rust-library.md)), we control the unit and should always supply seconds explicitly.

The JS API surface confirms the field exists on decoded changes and that `time` is documented in seconds at the type boundary; see the JS reference under [automerge.org/automerge/api-docs/js](https://automerge.org/automerge/api-docs/js/) (e.g. `DecodedChange`), with the seconds-vs-milliseconds caveat from #965 above.

## 2. Deriving a sync-safe "last updated" from change metadata

The change graph is a DAG. The **heads** are the terminal changes of that DAG — the current frontier of history:

- Rust: `get_heads(&self) -> Vec<ChangeHash>` returns *"the heads of this document"*; `get_change_by_hash(hash) -> Option<Change>` resolves a hash to its full `Change` (from which you read `.timestamp()`); `get_changes(have_deps) -> Vec<Change>` returns changes not covered by `have_deps` — [`automerge::Automerge`](https://docs.rs/automerge/latest/automerge/struct.Automerge.html).
- JS: `getHeads(doc)` — *"Get the hashes of the heads of this document"* — [getHeads](https://automerge.org/automerge/api-docs/js/functions/getHeads.html).

**Approach:** call `get_heads()`, resolve each head hash via `get_change_by_hash()`, read `.timestamp()`, and take the max. (More thoroughly, one could scan all changes via `get_changes(&[])`, but the most-recent edit is at the frontier, so the heads are the relevant set — after a merge there may be multiple heads, one per concurrent branch, and the max across them is the latest of those branch tips.)

**Is "max change time across heads" the right notion of latest edit?** It is the best signal Automerge itself provides, but it comes with correctness caveats that the primary sources make explicit:

- **The clock is the writing device's, and skew is real.** The time is whatever the committing device supplied; the docs describe it as *"purely advisory"* and it is *"not used in conflict resolution"* — [CommitOptions](https://docs.rs/automerge/latest/automerge/transaction/struct.CommitOptions.html). Two devices with skewed clocks can produce change times that don't reflect true causal order, so `max(time)` can disagree with the actual latest logical edit.
- **`time` can be 0 / unset.** As shown in §1, the Rust core does not auto-populate `time`; a committer that omits it yields `timestamp == 0`. Any device (or non-LocalCents tooling) that writes without setting time contributes a `0`, which a naive `max` would ignore but which signals the value is not universally guaranteed.
- **Causal ordering ≠ wall-clock ordering.** Automerge's ordering guarantees are structural (the DAG / operation IDs), not temporal. The `time` field is decorative metadata riding along the causal structure.

So: max-over-heads is a reasonable, sync-safe *display* value, but it is a heuristic, not a guarantee of the true latest edit under clock skew.

## 3. What autosurgeon exposes

autosurgeon is scoped to mapping Rust structs to/from Automerge documents via the `Reconcile` and `Hydrate` traits (plus `hydrate`, `reconcile`). Its README/quickstart covers putting/getting data, forking, and merging, but **does not expose change history, timestamps, or heads** — see [autosurgeon README](https://github.com/automerge/autosurgeon/blob/main/README.md) and the [crate docs](https://docs.rs/autosurgeon/latest/autosurgeon/).

Crucially, autosurgeon operates *on* an `automerge::AutoCommit` / `automerge::Automerge` document you own — its examples call `reconcile`/`hydrate` against a live `AutoCommit`. So we retain direct access to the core `automerge` crate on the same document and can call `get_heads()` / `get_change_by_hash()` / `.timestamp()` ourselves. **Conclusion: to derive a last-updated from change metadata, we would drop to the core `automerge` crate API on the same document handle; autosurgeon adds nothing here and does not get in the way.**

## 4. Alternative: store our own `updated_at` field inside the document

Option (a): app-maintained `updated_at` scalar written into the Automerge doc (e.g. a top-level key on the Book) on every edit.
Option (b): derive from change metadata (§2).

**What happens to (a) on merge?** `updated_at` would be a normal map value (an LWW register). If two devices edit concurrently and both set `updated_at`, Automerge resolves the conflict **deterministically but by operation ID, not by the timestamp value**:

- The winner is *"the same on all nodes,"* and *"'last writer wins' here is based on the internal ID of the operation, not a wall clock time"* — [Conflicts, automerge.org](https://automerge.org/docs/reference/documents/conflicts/). The internal ID is a (counter, actor ID) pair, ordered by counter with actor ID as tiebreaker.
- The under-the-hood merge rule confirms it: for concurrent puts to the same key, Automerge *"choose[s] one arbitrarily, but in such a way that all nodes agree,"* and **time is not used** — [Merge Rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/).
- Losing values are preserved (multi-value register) and readable via `getConflicts`; keys are the operation IDs of the writers — [Conflicts](https://automerge.org/docs/reference/documents/conflicts/) / [getConflicts](https://automerge.org/automerge/api-docs/js/functions/getConflicts.html).

**Key consequence:** for a scalar `updated_at`, the register's *winner is not necessarily the larger timestamp*. Under concurrent edits, Automerge may surface the value from the operation with the higher operation ID even if that device's clock read *earlier*. So a plain stored `updated_at` scalar does **not** reliably give "the latest edit" after a concurrent merge — it gives an arbitrary-but-deterministic one of the concurrent values. To recover "latest," we would have to read all conflicting values via `getConflicts` and take the max ourselves — which is essentially the same clock-skew-limited computation as deriving from change metadata, just stored redundantly in the doc.

## 5. Timezone / format basis

- **Change `time`:** unix timestamp in **seconds**, and unix time is by definition UTC-based (seconds since 1970-01-01T00:00:00Z). Source: the `CommitOptions` doc phrase *"unix timestamp (in seconds)"* plus the crate example using `SystemTime::UNIX_EPOCH … .as_secs()` — [CommitOptions](https://docs.rs/automerge/latest/automerge/transaction/struct.CommitOptions.html).
- **In-document `Timestamp` data type (distinct from change time!):** the [Document Data Model](https://automerge.org/docs/reference/documents/) defines Automerge's `Timestamp` value type as *"the integer number of milliseconds since the unix epoch (midnight 1970, UTC)"* — **milliseconds, UTC**.

**Do not confuse the two units.** A change's advisory `time` is **seconds**; an in-document `Timestamp` value is **milliseconds**. If we store our own `updated_at` as an Automerge `Timestamp` scalar (option a), it is milliseconds-since-epoch UTC; if we derive from change metadata (option b), it is seconds-since-epoch UTC. The Elixir side must format accordingly (e.g. `DateTime.from_unix(secs, :second)` vs `DateTime.from_unix(ms, :millisecond)`), always treating the base as UTC.

## Recommendation for LocalCents

Weighed against the constraint *"no filesystem assumptions; the timestamp should reflect the latest edit"*:

- **Both options are filesystem-independent** and travel with the document through sync — either satisfies the #61 requirement to abandon file mtime.
- **Neither option can perfectly guarantee "latest edit" under multi-device clock skew**, because Automerge's `time` is advisory and its conflict resolution ignores wall-clock time (§4). This is a genuine limitation the primary sources do not solve; any "last updated" we show is a best-effort, clock-dependent heuristic. We should not present it as authoritative ordering.

Given that, the **derive-from-change-metadata approach (option b)** is the better default:

1. It requires **no schema change** to the Book document and no write-path discipline (no risk of forgetting to bump `updated_at` on some edit path). The timestamp is a pure function of history already present in the doc.
2. It is honest about its meaning: "time of the most recent change at the document heads," which is exactly the sync-safe frontier notion.
3. It composes cleanly with our stack — autosurgeon leaves the core `automerge` document accessible, so a small NIF that calls `get_heads()` → `get_change_by_hash()` → `.timestamp()` → max gives us the value (§2, §3).

The **stored-`updated_at`-field approach (option a)** is *not* recommended as the primary mechanism: under concurrent merges the LWW register winner is chosen by operation ID, not by timestamp value (§4), so a naive read can show a *stale* value even though a newer edit exists; recovering "latest" then requires reading `getConflicts` and taking a max — the same clock-limited computation as option b, but with added write-path burden and a larger document.

**Caveats to carry forward (must-do if we ship option b):**
- Always commit changes from the Rust side with an explicit `CommitOptions::set_time(<unix seconds>)` so change times are populated and in the correct (seconds) unit — the core does *not* default it, and JS defaults it wrong ([#965](https://github.com/automerge/automerge/issues/965)).
- Guard against `time == 0` (unset) changes when computing the max.
- Treat the displayed value as advisory; clock skew across devices means it is not a reliable causal ordering.
- Format on the Elixir side as **seconds since unix epoch, UTC**.

**What the primary sources do NOT settle:** which concurrent branch's clock is "correct," and any recommended reconciliation of clock skew — Automerge deliberately treats `time` as advisory and out of scope for conflict resolution. Any policy there is ours to define.

---

*Saved to `docs/research/automerge-last-updated.md`. I created the `docs/research/` directory as the new home for research notes (the repo previously had none).*
