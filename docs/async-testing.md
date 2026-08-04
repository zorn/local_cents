# Async Testing

Every test module in LocalCents runs `async: true`. This guide is the standard that keeps it that way: what makes a module serial, the one mechanism we use to avoid it, and what to do when you write code that seems to need a global.

It is a working guide, not the evidence. The survey behind it — how ExUnit schedules async and sync modules, how `$callers` propagates, what Ecto's sandbox and Oban's suite do about the same problem — is [Test Isolation Patterns for Process-Wide State](test-isolation-patterns-for-global-state.html). Read that when you want to know *why* one of the rules below is the rule.

## Why every module is async

`async: false` does not cost you one module's worth of wall clock. ExUnit drains every async module first, then runs the sync ones **one at a time** — so serial modules cost the sum of their runtimes, with no overlap and no benefit from `max_cases`. Before this standard existed, six modules were serial and they were 16.4s of a 20.2s suite. Making them concurrent took the suite to 7.6s with an empty serial tail.

That ratio is why "just mark it `async: false`" is not a neutral choice. A single serial module is cheap; the habit of reaching for it is not, because the tail grows by addition and never by overlap.

## What actually forces a module serial

Only one thing: **the test changes state that another concurrently-running test can observe.** Slow tests, side-effecting tests, and tests that spawn processes are all fine async. A test that writes to a shared cell is not.

In practice that means a process-wide singleton — the application env, the Logger level, a named process, an ETS table, the current working directory. If you are reaching for `async: false`, name the specific cell you are mutating first. Usually there is a way to stop mutating it.

Three ways, in the order to try them.

### 1. Take the value as an argument

The best fix, and the one that needs no machinery. `LocalCents.Tracking` accepts a `:books_dir` option and threads it down into `LocalCents.Tracking.BookServer`, so the unit and context tests pass their own `@tag :tmp_dir` directory and never touch a global at all. An argument is visible in the signature, cannot resolve wrong, and costs nothing at runtime.

Reach for this first every time. The reasoning in full: [Avoiding `async: false` Tests](avoiding-async-false-tests.html).

### 2. Claim the value for your process tree

When there is no caller to inject the value — a LiveView calls the dir-free `LocalCents.Tracking` API from its own process, and nothing in the test can hand it a directory — use `LocalCents.ProcessConfig`.

Production reads the setting from the application env as usual. In the test build, `get/2` first looks the key up in the calling process's tree (its own dictionary, its `$callers`, its ancestors) and only falls back to the application env when no process in that tree has claimed a value:

```elixir
# In the test's setup — claims the value for this test and everything it spawns:
ProcessConfig.put(:books_dir, dir)

# In production code, anywhere the test reaches:
ProcessConfig.get(:books_dir)
```

The claim reaches further than it looks. `Phoenix.LiveViewTest` passes the test pid as a `"caller"` join param and LiveView writes it into the view's process dictionary, so a LiveView driven by `PhoenixTest` resolves the claim of the test driving it — and so does a `Task` that LiveView spawns, because `Task` prepends to `$callers` as it goes. Two tests running at once resolve their own values.

`LocalCents.BooksDirHelper` is the worked example; `setup :with_temp_books_dir` is all a feature test needs.

### 3. Swap the component, don't isolate the state

Sometimes the cheapest answer is a test-local implementation rather than a test-local value. Oban's suite runs 35 of 35 modules async partly by substituting an isolated peer and notifier for the ones that coordinate globally. If you find yourself scoping a setting whose only job is to switch off a subsystem, consider whether the subsystem should be swappable instead.

### The exception that stays

There is no rule against `async: false`; there is a rule against reaching for it before the three above. A genuinely node-wide mutation with no seam — the ExUnit docs' own example is `File.cd/1` — is a legitimate serial module. Say why in a comment on the `use` line, naming the cell, so the next reader can tell a considered decision from an unexamined one.

## The one sharp edge: work that outlives the test

A claim lives in the test process's dictionary and dies with it. **A process still working after the test returns can no longer resolve it** and silently falls back to the application env.

This is not hypothetical. The Library window seeds a demo library in a task spawned by `start_async`. A test that asserted the loading state and returned left that task writing Books into the shared fallback directory a beat later, because by then the test process it would have resolved through was gone.

The fix is to not abandon work you started — wait for it to settle before the test ends:

```elixir
conn
|> visit(~p"/library")
|> assert_has("[role='status']", text: "Setting up your demo library")
|> refute_has("[role='status']", timeout: 10_000)
```

This is the known limit of a process-tree lookup, and the reason ownership-server libraries like `nimble_ownership` exist: they hold the resource outside the test process so it can still be resolved (and asserted on) after that process exits. We do not need that yet — nothing we scope has to be readable in `on_exit`, which also runs in a separate process.

A related shape worth knowing: `LocalCents.Tracking.BookServer` processes are supervised by the application, not by the test, so they outlive the test that opened a Book. They are safe because each one is handed its directory as a `start_link` argument and holds it in state — the one process a process-tree walk could not reach is also the one that does not need reaching. Keep it that way.

## Two settings that read oddly on purpose

`config/test.exs` carries two settings whose shape is driven by this standard.

**The primary Logger level is `:debug` while the default handler stays at `:warning`.** `ExUnit.CaptureLog` cannot see a message the primary level already filtered, so a test asserting on a debug log would otherwise have to lift the level at runtime — a node-wide mutation whose behavior ExUnit explicitly documents as undetermined under async. Splitting the two lets the capture see everything while the console prints what it always did.

**`:books_dir` still has an application-env value.** It is the fallback for tests that never write a Book, and a backstop so a run can never touch the real application-support location. Feature tests claim their own directory over the top of it.

## Checklist for a new test module

- Start at `async: true`. Only drop it after you have named the shared cell and ruled out all three options above.
- Need a books directory? `@moduletag :tmp_dir` and pass it explicitly for unit and context tests; `setup :with_temp_books_dir` for feature tests.
- Do not call `Application.put_env/3` in a test. It is the mutation this whole guide exists to avoid, and it is the one thing that will make a passing suite fail for someone else at a different seed.
- If your test starts background work, make it wait for that work to finish.
