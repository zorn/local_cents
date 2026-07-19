# Testing Strategy: Public API over Implementation Details

> Research note feeding [issue #79](https://github.com/zorn/local_cents/issues/79) — grounding our "favor a context's public API over its internal modules" preference in what the book actually argues and in what our tests actually do.
> The primary source is Vladimir Khorikov's *Unit Testing Principles, Practices, and Patterns* (Manning, 2020), read from the reading notes at `notebook/Library/Unit Testing Principles, Practices, and Patterns.md` and the fuller source text at `notebook/Library/_sources/unit-testing.txt` (cited by chapter/section number below). Project claims cite the actual test and source files by `path:line`. No blog posts or secondary write-ups were used as authorities.

## Why this note exists

Issue #79 (raised reviewing #75's `test/local_cents/tracking/book_store_test.exs`) wants a written preference: tests should exercise the `LocalCents.Tracking` **public API** rather than its internal modules (`BookStore`, `BookServer`, `ExAutomerge`, `BookDocument`), because testing internals costs upkeep as those internals evolve without protecting behavior we actually promise. It also asks *when* testing an internal module is nonetheless justified (e.g. a NIF boundary), and how the rule interacts with our `boundary`/subcontext structure.

The one important refinement this note makes: the book's real principle is **not** "test the public API." It is **"test observable behavior, not implementation details."** "Test through the public API" is a very good *proxy* for that, and the right default — but the more precise principle is what licenses our justified exceptions, so it is worth adopting the precise version.

## 1. What the book actually argues

### The four pillars, and why one of them is the whole game here

Every test is scored on four pillars (Ch 4): **protection against regressions**, **resistance to refactoring**, **fast feedback**, and **maintainability**; a test's value is roughly the *product* of the four, so a zero on any one makes the test worthless. You cannot maximize the first three at once — but **resistance to refactoring is non-negotiable** (it is effectively binary; you either have it or you don't), so the real trade-off left to tune is protection vs. speed (`notebook/Library/…Patterns.md` "Big ideas", Ch 4 distillation).

Resistance to refactoring is the pillar #79 is really about. A test lacking it produces **false positives**: it fails when you refactor the implementation even though behavior is unchanged. False positives are "the silent killer" — they train the team to ignore failures and erode trust in the whole suite. Their root cause is named precisely: **coupling tests to implementation details**. The corrective rule is *"assert the end result the SUT produces, never the steps it took,"* and the discipline is *"write tests black-box (through the public API); analyze them white-box"* (Ch 4; source `unit-testing.txt:2659`, `:3031`).

### The precise principle: observable behavior ≠ public API

The book is explicit that "test the public API" is a proxy, not the target. It classifies all production code on **two independent axes** — public/private API, and observable-behavior/implementation-detail (Ch 5.2.1, `unit-testing.txt:3282`). Code is **observable behavior** only if it "expose[s] an operation… or a state that helps the client achieve one of its goals," and *"whether the code is observable behavior depends on who its client is and what the goals of that client are"* — the client may be *"client code from the same code base, an external application, or the user interface"* (`unit-testing.txt:3294`–`3302`).

In a **well-designed** system the two axes line up: observable behavior is public, implementation details are private (`unit-testing.txt:3304`). Because they usually coincide, "test through the public API" is the right default. But they are not the same thing, and the gap is exactly where the justified exceptions live (§4).

### The London vs. classical split, and mocking

The book sides with the **classical (Detroit)** school over the **London (mockist)** school. A "unit" is a unit of *behavior*, not a class; you isolate *tests* from each other, not every class from its collaborators (Ch 2). The London school's over-mocking causes **over-specification** — coupling to implementation details — which is the same failure mode #79 wants to avoid one level up (context-internal calls are "intra-system" collaboration; asserting on them is fragile; Ch 5). The practical rule: **mock only unmanaged dependencies** (things other apps can see, e.g. an SMTP server); use the **real thing** for **managed** dependencies reachable only through your app (e.g. the database/filesystem) and assert final state (Ch 8).

### The four types of code

Code is sorted by complexity/domain-significance × number of collaborators (Ch 7): **domain model & algorithms** (test hard with unit tests — best ROI), **trivial code** (don't test), **controllers** (test briefly with integration tests), and **overcomplicated code** (refactor into the first two). The **functional-core / mutable-shell** split (Ch 6) is the tool that keeps the domain in the high-ROI quadrant — and it maps almost directly onto idiomatic Elixir (pure functions for the domain, processes/boundaries for side effects), a connection the notes call out explicitly (`…Patterns.md` "Notes & connections").

### Where the user's paraphrase needs sharpening

| User's paraphrase | The book's actual position |
|---|---|
| "Validate the public API." | Validate **observable behavior**. Testing through the public API is the *default technique* for doing that, not the principle itself (Ch 5.2.1). |
| "Avoid testing private implementation." | Correct, and the book is emphatic — never widen access just to test (Ch 11.1). But it carves out an explicit exception: a member that is *private yet part of observable behavior* (it fulfills a contract with an out-of-process client) is fine to test directly (Ch 11.1.3, below). |
| (implied) private = never test | The reason private methods are usually off-limits is that *"those private methods are a proxy for implementation details"* — "testing private methods isn't bad in and of itself" (`unit-testing.txt:8246`). |

So the paraphrase is directionally right and a fine slogan, but the operative rule is "observable behavior over implementation details," which both explains the default *and* draws the exception line cleanly.

## 2. How this maps to LocalCents' architecture

The `boundary` library already encodes the public/private axis at compile time. `LocalCents.Tracking` is a top-level boundary whose **public API is its root module**, exporting only the data contract (`Book`, `Category`, `Expense`) plus `Supervisor` for the supervision tree; `BookServer`, `BookStore`, and `ExAutomerge` stay private and a cross-boundary call to them is a compile error (`lib/local_cents/tracking.ex:37`, moduledoc at `:1`–`:29`; `docs/module-boundaries.md`). Boundary enforces the same distinction Khorikov draws — the doc even uses `LocalCents.Tracking.ExAutomerge.decode(book_bytes)` as its example of a forbidden "couples the caller to an implementation detail" call (`docs/module-boundaries.md:18`–`:25`).

Mapping the book's vocabulary onto the context:

| Book concept (Ch 7) | LocalCents module | Evidence |
|---|---|---|
| Domain model & algorithms (pure, few collaborators — best unit-test ROI) | `BookDocument` — the **functional core**, "pure data in / data out — no process, no NIF" | `lib/local_cents/tracking/book_document.ex:1`–`:14` (ADR 0014); `test/…/book_document_test.exs:1`–`:5` |
| Controller / application service (orchestration, I/O, thin) | `Tracking` (facade) + `BookServer` (process shell that "wraps each command with the side effects") | `lib/…/tracking.ex:56`–`:69`; `lib/…/book_server.ex:1`–`:14` |
| Infrastructure with high algorithmic complexity + a cross-app boundary | `ExAutomerge` — the Rust/Automerge CRDT codec (NIF) | `lib/…/ex_automerge.ex:1`–`:20` |
| Infrastructure / repository over a managed dependency (filesystem) | `BookStore` — `.lcbook` read/write/list | `lib/…/book_store.ex` |

This is a textbook **functional-core / process-shell** arrangement (ADR 0014), which is exactly the Elixir-flavored **Humble Object** the book recommends for keeping the domain in the high-ROI quadrant while pushing side effects to a thin shell (Ch 6, Ch 7).

The bulk of our behavioral coverage already sits at the public API: `test/local_cents/tracking_test.exs` is ~40 tests driving only `LocalCents.Tracking` — create/open/close, expenses, categories, `updated_at`, broadcasts, `not_open` errors — against a **real** temp books directory (`with_temp_books_dir`), asserting end state, never internal steps (`test/…/tracking_test.exs:1`–`:13`, and throughout). That is the book's ideal: black-box tests over a controller, using the real managed dependency (Ch 8). The functional core is likewise covered directly at `BookDocument` — but note that is *not* an exception to the rule, because `BookDocument`'s functions **are** observable behavior (a pure module whose public functions are its contract), tested output-based, the highest-quality style (Ch 6).

## 3. The synthesized guiding principle

> **Test the behavior LocalCents promises, through the narrowest public surface that can observe it.** For a context, that surface is its boundary API (`LocalCents.Tracking`): assert the end result a command produces, never the internal steps it took. Reach past the API into an internal module (`BookServer`, `BookStore`, `ExAutomerge`) only when the guarantee under test is a real, observable behavior that the context API genuinely cannot express — a process-lifecycle or durability guarantee, a NIF/CRDT boundary contract, or an algorithm too complex to pin down end-to-end. When in doubt, prefer the API: an internal-module test that would break under a behavior-preserving refactor is coupled to an implementation detail and should move up or be deleted.

Rationale, in the book's terms: the boundary API is where our **observable behavior** and our **public API** are designed to coincide (Ch 5.2.1; `boundary` enforces it). Tests there maximize **resistance to refactoring** — the non-negotiable pillar (Ch 4) — because we can restructure `BookServer`/`BookStore`/`ExAutomerge` freely as long as `Tracking`'s contract holds. Tests that assert on internal collaboration ("intra-system communication," Ch 5) are the fragile category the book warns against, and the exact upkeep cost #79 names.

## 4. When testing an internal module IS justified

The license comes straight from the book's own carve-out. Ch 11.1.3 ("When testing private methods is acceptable") gives the `Inquiry`/ORM example: a **private** constructor that is nonetheless **part of observable behavior**, because *"this constructor fulfills the contract with the ORM, and the fact that it's private doesn't make that contract less important: the ORM wouldn't be able to restore inquiries from the database without it"* (`unit-testing.txt:8283`). The out-of-process client (the ORM) makes the private member observable. The second carve-out is algorithmic: the black-box rule's *"only exception is when the test covers utility code with high algorithmic complexity"* (`unit-testing.txt:3031`; also Ch 7 on complex infrastructure algorithms, `:1047`).

Both carve-outs apply concretely here.

**(a) `ExAutomerge` — the NIF / CRDT boundary (both carve-outs at once).** `test/…/ex_automerge_test.exs` exercises "the Rust NIF boundary directly as a codec" (`:1`–`:6`): decode/reconcile round-trips, absent-cost → `nil`, the advisory change-time `document_updated_at` derivation, and — the load-bearing part — **CRDT merge semantics**: concurrent delete-and-edit of different expenses both survive (`:244`–`:297`), merge is commutative (`:221`), identity-keyed rename-vs-delete of categories both survive (`:103`–`:147`). This is justified on two independent grounds:
- It is **observable behavior with an out-of-process client** — exactly the `Inquiry`/ORM shape. The merge contract's client is *another device's document arriving over sync*; that "latest edit survives a concurrent merge" guarantee is a promise to the outside world (see `docs/research/automerge-last-updated.md` and ADR 0015), and it is invisible at the single-process `Tracking` API. In the book's mock vocabulary this is closer to an **unmanaged** dependency (the CRDT format is visible to other apps/devices) than to the filesystem.
- It is **high-complexity algorithmic infrastructure** (a CRDT), the explicit exception to black-box-by-default (`unit-testing.txt:3031`). The module deliberately holds *no domain logic* (`lib/…/ex_automerge.ex:4`–`:7`), so these tests pin down the codec/merge algorithm and nothing we'd otherwise refactor freely.

**(b) `BookServer` — the process/durability boundary.** `test/…/book_server_test.exs` asserts guarantees that are real observable behavior but *not expressible through the pure `Tracking` return values*: **persist-then-commit ordering** (a failed persist keeps in-memory state and fires no broadcast, `:22`–`:41`), an invalid command doesn't crash the server (`:43`–`:52`), and the `restart: :transient` **regression guard** that a just-closed Book is not resurrected by the DynamicSupervisor (`:65`–`:79`). Durability-under-failure and process-lifecycle are promises to the user (no silent data loss; close means closed), and observing them requires reaching into the process (`BookServer.alive?/1`, `Registry.lookup`, chmod'ing the dir). These are justified — but note they still assert **outcomes** (state preserved, no broadcast, process gone), not internal call sequences, so they keep resistance-to-refactoring.

**(c) `BookStore` — the weakest-justified, and that's expected.** `test/…/book_store_test.exs` tests the filesystem repository directly: atomic overwrite leaves no `.tmp` behind (`:33`–`:40`), a failed rename cleans up (`:42`–`:50`), `path/1`/`load`/`delete` round-trips. The book's guidance for this quadrant is the least favorable to per-module tests: the filesystem is a **managed** dependency, so the norm is to use it *for real inside integration tests through the controller* and *"don't test repositories directly"* except for complex reads (Ch 8, Ch 10). Most of what `book_store_test` asserts (round-trip persistence, enumeration) is already re-covered through `Tracking` (`tracking_test.exs` open/close/reopen, `list_books`). The genuinely store-specific bits — temp-file atomicity and cleanup on a failed rename — are a small algorithmic/durability core worth keeping close, but the file as a whole is the prime candidate to thin out later. Per #79, **#75's per-module tests stay as-is for now**; this is simply where future consolidation would start.

## 5. How it interacts with the boundary / subcontext structure

- **`boundary` and the test rule are the same principle at two altitudes.** Boundary forbids *production* code from calling `Tracking`'s internals (compile error); this strategy asks *test* code to prefer the same front door. The exceptions in §4 are the reason tests may still name `BookServer`/`ExAutomerge` while production code may not — tests legitimately probe observable behaviors that live at internal seams, but they should remain the minority.
- **The functional core is not an exception.** `BookDocument` is private to the boundary, yet testing it directly is fully aligned with the rule, because its public functions *are* observable behavior (the domain model, highest-ROI quadrant, output-based style). The mental model is "test observable behavior at the lowest-collaborator surface that owns it," not "only ever call `Tracking`."
- **Adding a subcontext later doesn't change the rule.** When a second context appears (the `docs/module-boundaries.md` "Adding a new context" recipe), its tests default to its own boundary API, with the same NIF/process/algorithm carve-outs available if it grows equivalent seams.
- **Minor doc drift to fix in passing:** `docs/module-boundaries.md:46` still lists Tracking's exports as `Book, Expense` and describes `Book` as an opaque `binary()`, whereas `lib/local_cents/tracking.ex:37` now exports `[Book, Category, Expense, Supervisor]` and `Book` is a struct. Not material to this strategy, but worth correcting when that doc is next touched.

## 6. Recommendations for the eventual `docs/` guidance

The written testing doc (issue #79 suggests `docs/agents/` or a dedicated testing page; a `docs/testing-strategy.md` linked from `CODING_STANDARDS.md` fits our other standards) should say, in short:

1. **Default: test a context through its boundary API** (`LocalCents.Tracking`), asserting end results against real managed dependencies (the temp books dir), never internal call sequences. State the *why* in the book's terms: it protects **resistance to refactoring**, the non-negotiable pillar, and avoids the upkeep of tests coupled to internals.
2. **Frame the principle precisely** as "test observable behavior, not implementation details," with "through the public API" as the default technique — so the exceptions read as consistent, not as loopholes.
3. **Name the three justified reasons to test an internal module**, each tied to observable behavior the API can't express: (a) a **NIF / CRDT boundary** whose client is another device (`ExAutomerge` merge/round-trip); (b) a **process-lifecycle or durability guarantee** (`BookServer` persist-then-commit, `:transient` restart); (c) an **algorithmically complex internal** (the CRDT codec; atomic-write core). Require even these to assert outcomes, not steps.
4. **Point the functional core `BookDocument` at direct unit tests** as the high-ROI norm, explicitly noting it is *not* an exception to the API-first rule.
5. **Record the direction of travel without churn now:** `book_store_test.exs` largely duplicates persistence behavior already covered through `Tracking` and is the first candidate to thin toward integration-through-the-API, keeping only the store-specific atomicity/cleanup asserts. **Per #79, #75's per-module tests stay as-is for now** — the guidance sets the default for *new* tests, it is not a mandate to rewrite existing ones.
6. **Cross-reference `docs/module-boundaries.md`** so readers see the compile-time (production) and convention (test) halves of the same public/private principle together.
