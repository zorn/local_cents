# Avoiding `async: false` in the Test Suite

> Research note feeding [issue #78](https://github.com/zorn/local_cents/issues/78) — several Tracking tests run `async: false` only because they share one global value, the `:books_dir` application env, and the helper that redirects it (`LocalCents.BooksDirHelper`) mutates that global per test. This note grounds "how to make those tests async" in primary sources and recommends a redesign that fits our functional-core / process-shell architecture.
>
> Primary sources: the official [`Application`](https://elixir.hexdocs.pm/Application.html), [`Task`](https://elixir.hexdocs.pm/Task.html), [`ExUnit.Case`](https://ex-unit.hexdocs.pm/ExUnit.Case.html), and [`ExUnit.Callbacks`](https://ex-unit.hexdocs.pm/ExUnit.Callbacks.html) docs, and the [`Ecto.Adapters.SQL.Sandbox`](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html) docs (the reference design for "a shared global resource made concurrency-safe by scoping it to the owning process"). Project claims cite repo files by `path:line`. Elixir Forum threads appear in a clearly-marked community-signal section as *secondary* sources — used to surface consensus and gotchas, with every factual claim traced back to the primary source it belongs to.
>
> **Status:** the "Recommendation for LocalCents" below was implemented in issue #78 — `BookStore.books_dir/0` became `BookStore.default_dir/0`, the filesystem functions and `BookServer` now take an explicit directory, and the unit/context tests run `async: true` via `@tag :tmp_dir`. The code snippets below describe the *pre-refactor* state they set out to fix.

## The problem, precisely

Before #78, `BookStore.books_dir/0` resolved the directory that holds `.lcbook` files by reading the application environment at call time:

```elixir
# lib/local_cents/tracking/book_store.ex:34
def books_dir do
  dir =
    Application.get_env(:local_cents, :books_dir) ||
      Path.join(:filename.basedir(:user_data, "LocalCents"), "books")

  File.mkdir_p!(dir)
  dir
end
```

Every filesystem entry point funnels through this one read — `save/2`, `load/1`, `delete/1`, `list_ids/0`, and `path/1` all call `books_dir/0` (`lib/local_cents/tracking/book_store.ex:111`, `:128`). To give a test its own directory, `LocalCents.BooksDirHelper` mutates the global env and restores it on exit:

```elixir
# test/support/books_dir_helper.ex:16
dir = Path.join(System.tmp_dir!(), "lc_books_#{System.unique_integer([:positive])}")
previous = Application.get_env(:local_cents, :books_dir)
Application.put_env(:local_cents, :books_dir, dir)

ExUnit.Callbacks.on_exit(fn ->
  File.rm_rf(dir)
  Application.put_env(:local_cents, :books_dir, previous)
end)
```

The helper's own moduledoc states the consequence: "Because it mutates the global `:books_dir` application env, test modules using it must run with `async: false`" (`test/support/books_dir_helper.ex:6`). Five test modules inherit that constraint and say so in a header comment:

- `test/local_cents/tracking_test.exs:2` — `use ExUnit.Case, async: false`
- `test/local_cents/tracking/book_server_test.exs:2`
- `test/local_cents/tracking/book_store_test.exs:2`
- `test/local_cents/demo_seeding_test.exs:2`
- `test/local_cents_web/live/book_live_test.exs:2`, `library_live_test.exs:2`, `book_categories_live_test.exs:2` (each `use LocalCentsWeb.FeatureCase, async: false`)

The base config also sets a single shared value — `config :local_cents, :books_dir, Path.join(System.tmp_dir!(), "local_cents_test_books")` (`config/test.exs:17`) — which, without the per-test override, every test would share.

## 1. Why the application environment is the wrong home for per-test config

The application environment is a process-independent, global, mutable key/value store. The `Application` docs are explicit that this is what it is and what it is *not* for.

- **It is effectively global storage.** Under "Application environment in libraries," the docs advise: *"it is generally recommended to avoid the application environment, as the application environment is effectively a global storage"* ([`Application`](https://elixir.hexdocs.pm/Application.html)). `Application.put_env/4` and `get_env/3` read and write one table shared by every process in the node — there is no per-process or per-test scoping.
- **It is meant for compile-time / boot-time configuration, not runtime values that vary per call.** The docs frame the environment around a "Compile-time environment vs. runtime environment" distinction and note that runtime reads happen when a component "effectively starts" (e.g. `MyApp.DBClient` reading `:db_host` at startup). It is configuration you set once from `config/*.exs` and read, not a place to stash values that differ between concurrent callers.

The async consequence follows directly from ExUnit's own contract. `async: true` "configures tests in this module to run concurrently with tests in other modules… It should be enabled only if tests do not change any global state" ([`ExUnit.Case`](https://ex-unit.hexdocs.pm/ExUnit.Case.html)). `Application.put_env/4` changes global state *by definition*: if test A points `:books_dir` at `/tmp/a` while test B concurrently points it at `/tmp/b`, both `books_dir/0` reads race on one table and each test can observe the other's directory. `on_exit` restoration does not rescue this — it fixes ordering *within* a serial run, but concurrent writers still interleave. So any test that relies on a per-test `:books_dir` value is *forced* to `async: false`. The global read in `books_dir/0` is the entire reason these modules serialize.

## 2. The canonical patterns for making such tests async (from primary docs)

Four idioms, each backed by a primary source, address "shared global state forces serial tests."

### 2a. Pass configuration explicitly as arguments / start options (dependency injection)

The most direct fix is to stop reading global state at runtime and instead receive the value as a parameter — a function argument, a `GenServer.start_link/3` option, or `init/1` state. Once a value arrives as an argument, each caller (each test) supplies its own, and there is no shared table to race on, so `async: true` becomes safe under ExUnit's rule that tests must "not change any global state" ([`ExUnit.Case`](https://ex-unit.hexdocs.pm/ExUnit.Case.html)).

This is already the house idiom in `LocalCents.Tracking`: `create_book/2` injects `now`, `add_expense/4` injects both `now` and `today`, and the new-Expense/Category ids are generated at the boundary and passed inward (`lib/local_cents/tracking.ex:56`, `:228`, `:230`, `:317`). The docstrings say so outright — "defaults to the current time and is injectable for tests" (`lib/local_cents/tracking.ex:53`). The books directory is the one remaining *ambient* dependency that hasn't been converted to an injected argument.

For process state, `ExUnit.Callbacks.start_supervised!/2` starts a process under the test supervisor and is "guaranteed to exit before the next test starts" ([`ExUnit.Callbacks`](https://ex-unit.hexdocs.pm/ExUnit.Callbacks.html)), so a per-test process (holding, say, a per-test directory in its state) is created and torn down with no cross-test bleed and no manual cleanup.

### 2b. Per-test isolation keyed to the test process: the `:tmp_dir` tag

ExUnit already ships the exact "each test gets its own directory" primitive. Tagging a test `@tag :tmp_dir` (or a whole module via `@moduletag`) makes ExUnit create a temp directory and put its path in the test `context`. The docs state the isolation guarantee verbatim:

> "The temporary directory path is unique (includes the test module and test name) and thus appropriate for running tests concurrently." ([`ExUnit.Case`](https://ex-unit.hexdocs.pm/ExUnit.Case.html))

Because the path is derived from the module and test name (not a shared global), two concurrent tests get two different directories with no coordination — the same property `BooksDirHelper` builds by hand with `System.unique_integer/1`, but supplied by the framework and *already async-safe*. The remaining gap is only that our code must *receive* that path (2a) instead of reading it from global env; `:tmp_dir` provides the value, injection delivers it.

### 2c. The Ecto SQL Sandbox model — the reference design for our exact problem

`Ecto.Adapters.SQL.Sandbox` is the canonical answer to "one shared global resource (a database) that many `async: true` tests must use without stepping on each other." Its shape is directly analogous to our books directory: a single physical resource, made concurrency-safe not by mutating a global toggle but by **scoping access to the owning process**.

- **Ownership per test.** The sandbox is "a pool for concurrent transactional tests"; each test process checks out its own connection, and a test's changes are isolated to (and rolled back on) that connection ([`Ecto.Adapters.SQL.Sandbox`](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html)). The scoping key is the **test's pid**, not a global variable — which is exactly what issue #78 asks for ("keyed off the test pid/ref rather than a single global app-env value").
- **Reaching the owner from a spawned process.** When work happens in *another* process (a `Task`, a GenServer) that doesn't own the connection, the sandbox finds the owner two ways: an explicit `allow/3`, which assigns the owner's connection to the other process, and **automatic caller tracking** — "allowance can also be provided to processes via Caller Tracking" ([`Ecto.Adapters.SQL.Sandbox`](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html)).

The analogy to LocalCents: if `books_dir` were an owned, per-test resource looked up by the owning process (rather than a global env value), Tracking tests could run concurrently the way sandboxed Ecto tests do. The important caveat — see §3 — is *how* the owning process is found when the actual filesystem work runs inside a `BookServer`, which is where caller tracking enters.

### 2d. `$callers` propagation for per-process config

The mechanism behind the sandbox's automatic allowances is the `$callers` process-dictionary key. The `Task` docs, under "Ancestor and caller tracking," define it:

> "The list of callers of the current process can be retrieved from the Process dictionary with `Process.get(:"$callers")`. This will return either `nil` or a list `[pid_n, ..., pid2, pid1]` with at least one entry where `pid_n` is the PID that called the current process…" ([`Task`](https://elixir.hexdocs.pm/Task.html))

This is what lets a library resolve per-process configuration on behalf of a *different* process doing the work: the worker walks `$callers` to find the pid that spawned it and looks up that pid's checked-out resource. This is the precise trick that could, in principle, let a `BookServer` discover "which test owns me, and therefore which temp dir to use." The load-bearing limitation (§3): `$callers` is populated automatically for `Task`s and for `GenServer`/`proc_lib` children started *directly by the caller*, but LocalCents starts each `BookServer` through `DynamicSupervisor.start_child/2` under a long-lived supervisor, so the test pid is not automatically in the server's `$callers` — the same reason Ecto still needs an explicit `allow/3` for processes it can't reach via caller tracking.

## 3. Redesigning `books_dir` resolution for THIS codebase

The goal: `books_dir` resolves to a per-test value without any global mutation. Three realistic options, tied to what the modules actually do today.

**Where the directory is read from matters.** Two different kinds of caller read `books_dir/0`:

1. **The test process itself**, directly through `BookStore` and `Tracking` module functions: `Tracking.list_books/0` → `BookStore.list_ids/0`, `get_book/1`, and the closed-Book `rename_on_disk/3` → `BookStore.load/save` all run *in the caller's process* (`lib/local_cents/tracking.ex:104`, `:118`, `:194`–`:203`).
2. **The `BookServer` process**, for open-Book work: `init/1` calls `BookStore.load/1` and `commit/5` calls `BookStore.save/2` (`lib/local_cents/tracking/book_server.ex:277`, `:383`) — this runs in the GenServer, *not* the test process.

Any solution has to cover both, which is what makes this more than a one-line change.

### Option A — Inject `books_dir` as an argument (explicit dependency injection)

Thread the directory through the API the way `now`/`today` already are: `books_dir` becomes an argument to the `Tracking` functions that need it, is passed into `BookServer.start_link/1` (stored in `init/1` state, `lib/local_cents/tracking/book_server.ex:272`), and is passed into the `BookStore` functions as their first argument instead of being read from env. Tests get their directory from the `:tmp_dir` tag (§2b) and pass it in.

- **Pros.** No global state, no magic; `async: true` becomes trivially correct by ExUnit's rule. Mirrors the existing injection idiom (`lib/local_cents/tracking.ex:56`) so it reads as consistent, not novel. The `BookServer` naturally holds its dir in state — a server is already per-Book and per-test-supervised, so its directory travels with it and covers caller class #2 cleanly.
- **Cons.** The widest diff: `BookStore`'s five functions gain a `dir` parameter, `BookServer` state grows a field, and the `Tracking` facade must acquire the dir to pass down. For production that dir is the same platform default every time, so the facade would resolve the default once (still fine to read from a single boot-time config or the platform path) and pass it inward — the injection is really only *varying* in tests.

### Option B — Owned/registered directory looked up by the owning process (the Ecto-sandbox analog)

Introduce a tiny ownership lookup: a test registers its temp dir against its pid (an ETS table or `Registry`), and `books_dir/0` resolves by consulting that registry — via `$callers` (§2d) when the reader is a spawned process — before falling back to the platform default. This is the literal application of the sandbox pattern (§2c) to our filesystem.

- **Pros.** Smallest change at call sites — `books_dir/0` keeps its zero-arg shape; callers don't change. Conceptually the "right" model: per-test ownership keyed to the pid, exactly as #78 frames it.
- **Cons.** The caller-class-#2 problem bites hardest here. A `BookServer` is started by `DynamicSupervisor.start_child/2` (`lib/local_cents/tracking/book_server.ex:67`) under the long-lived `BookSupervisor` (`lib/local_cents/tracking/supervisor.ex`), so the test pid is *not* automatically in the server's `$callers` — we'd have to propagate callers manually through `ensure_started/1` or add an explicit `allow`-style handoff, reproducing the very complexity Ecto needs `allow/3` for. It also introduces test-only lookup logic into production `books_dir/0`, and a registered-but-crashed test could leave stale entries. High conceptual fit, high mechanism cost.

### Option C — Per-book directory carried in `BookServer` state only

A narrower version of A: only the *open-Book* path is injected (dir stored in `BookServer` state), while the library-enumeration path (`list_books/0`, `get_book/1`) still reads a resolved default. This under-serves the tests that enumerate the library (`demo_seeding_test.exs`, `library_live_test.exs`), which need the directory-listing side isolated too, so it does not by itself let those modules go async. Listed for completeness; not sufficient alone.

## 4. When `async: false` is still legitimately correct

Making these tests async is about removing *accidental* global state, not banning `async: false`. ExUnit's rule is conditional — concurrency "should be enabled only if tests do not change any global state" ([`ExUnit.Case`](https://ex-unit.hexdocs.pm/ExUnit.Case.html)) — so a test that *genuinely* touches process-wide or node-wide state should stay serial. Legitimate cases per the docs:

- **Tests that truly mutate real application-wide configuration** — e.g. deliberately exercising how the app reacts to an `Application.put_env` change itself (the config *is* the thing under test), not merely using it as a backdoor for a temp path.
- **Tests that reconfigure the logger or use `ExUnit.CaptureLog` in a way that touches global logger state**, where concurrent captures would interleave.
- **Tests coordinating a named singleton or globally-registered process** (a single named GenServer, a `:global` name, one ETS table used as a shared sink) that cannot be started per-test under the test supervisor.

The point of #78 is that the Tracking tests are in *none* of these categories: they don't test the config system, they just need an isolated directory — which §2b/§3 provide without any global mutation.

## Community signal (Elixir Forum — secondary sources)

These practitioner threads corroborate the direction above. They are *not* authorities; each factual claim below is anchored to the primary source in §1–§2.

- ["How to test with application env in `async: true`"](https://elixirforum.com/t/how-to-async-tests-with-application-env/67222) frames the exact problem — "this application env is global and therefore is very difficult to get right when testing with `async: true`" — and notes the clean fix is to pass configuration as explicit arguments rather than read global env (our Option A / §2a). It also points at helper libraries (Repatch) that *isolate* env per test; treat those as a bridge for code you can't refactor, not the target design.
- ["Using `Application.get_env` / `Application.put_env` in ExUnit tests"](https://elixirforum.com/t/using-application-get-env-application-put-env-in-exunit-tests/8019) reaches the same conclusion this note reaches from the primary docs: `put_env` "will break as soon as you use `async: true`," the popular workaround is `put_env` + `on_exit` restoration under `async: false` (precisely our current `BooksDirHelper`), and the async-safe alternative is a **process-dictionary lookup that checks the process tree before the global env** (the `ProcessTree` library, recommended there by a Scenic core member). That library is a concrete implementation of the `$callers` mechanism the [`Task`](https://elixir.hexdocs.pm/Task.html) docs define (§2d) and the [Ecto sandbox](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html) uses (§2c) — i.e. it is our Option B in library form, and it carries Option B's caveat that `DynamicSupervisor`-started processes need caller propagation to be reachable.
- ["In ExUnit is it possible to mark a single test as non-async?"](https://elixirforum.com/t/in-exunit-is-it-possible-to-mark-a-single-test-as-non-async/7243) confirms the granularity fact underlying §4: `async` is set per *module* (`use ExUnit.Case, async: …`), so isolating the shared resource lets a whole module flip to async rather than quarantining individual tests.

## Recommendation for LocalCents

**Adopt Option A (explicit injection) plus ExUnit's `:tmp_dir` tag, and retire `BooksDirHelper`'s `Application.put_env`.** Concretely:

1. Give `BookStore`'s filesystem functions an explicit directory parameter (drop the `Application.get_env` read in `books_dir/0`, `lib/local_cents/tracking/book_store.ex:34`).
2. Store the books directory in `BookServer` state via `start_link/1` → `init/1` (`lib/local_cents/tracking/book_server.ex:272`) so the open-Book path (caller class #2) carries its own dir with no `$callers` gymnastics.
3. Have the `Tracking` facade resolve the directory once (platform default in prod; the injected value in tests) and pass it down — the same shape as the `now`/`today` injection it already does (`lib/local_cents/tracking.ex:56`, `:228`).
4. In tests, tag modules `@moduletag :tmp_dir` and pass `context.tmp_dir` in; delete the global-mutation helper and flip the seven modules to `async: true`.

Why this over the alternatives: injection is *already the codebase's established idiom* for ambient dependencies, so it adds no new concepts and reads as consistent; `:tmp_dir` supplies the per-test-unique, concurrency-safe directory the framework already guarantees, replacing the hand-rolled `System.unique_integer` helper. Option B (the pure Ecto-sandbox analog) is conceptually the closest match to #78's "keyed off the test pid" wording and is the elegant answer *when the worker process is reachable via `$callers`* — but LocalCents starts each `BookServer` under a `DynamicSupervisor`, so caller tracking doesn't reach it automatically and we'd be reimplementing `allow/3`-style handoff for a problem injection solves outright. Reserve `async: false` for any future test that genuinely mutates app-wide config, the logger, or a named singleton (§4); the Tracking tests are none of those.
