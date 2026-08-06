# Async Testing

Every test module in LocalCents now runs `async: true`. This guide is the standard
that keeps it that way: what forces a module to be synchronous, the one mechanism
we use to avoid that, and what to do when you write code that seems to need a
global.

"Asynchronous test module" and "synchronous test module" are the terms this repo
uses, and they are defined in [Software Terms](software-terms.html) along with
**claim**, the verb for scoping a setting to your own process tree.

It is a working guide, not the evidence. The survey behind it — how ExUnit
schedules the two kinds of module, how `$callers` propagates, what Ecto's sandbox
and Oban's suite do about the same problem — is [Test Isolation Patterns for
Process-Wide State](test-isolation-patterns-for-global-state.html). Read that when
you want to know *why* one of the rules below is the rule.

## Why every module is asynchronous

We hold concurrency to be worth real effort, because a synchronous module costs
more than the wall clock it appears to. ExUnit finishes every asynchronous module
first, then runs the synchronous ones **one at a time** — so their cost is the sum
of their runtimes, with no overlap and no benefit from `:max_cases`.

That is why "just mark it `async: false`" is not a neutral choice. One synchronous
module is cheap; the habit of reaching for one is not, because that phase of the
run grows by addition and never by overlap. The rest of this guide is how we avoid
needing it.

## What actually forces a module to be synchronous

Only one thing: **the test changes state that another concurrently-running test
can observe.** Slow tests, side-effecting tests, and tests that spawn processes
are all fine asynchronous. A test that writes to a shared cell is not.

In practice that means a process-wide singleton, such as the application env, the
Logger level, a named process, an ETS table, or the current working directory. If
you are reaching for `async: false`, name the specific cell you are mutating
first. Usually there is a way to stop mutating it.

Three ways, in the order you should try them.

### 1. Take the value as an argument

The best fix, and the one that needs no machinery. `LocalCents.Tracking` accepts a
`:books_dir` option and threads it down into `LocalCents.Tracking.BookServer`, so
the unit and context tests pass their own `@tag :tmp_dir` directory and never
touch a global at all. An argument is visible in the signature, cannot resolve to
the wrong value, and costs nothing at runtime.

Reach for this first every time. The reasoning in full: [Avoiding `async: false`
Tests](avoiding-async-false-tests.html).

### 2. Claim the value for your process tree

When there is no caller to inject the value — a LiveView calls the dir-free
`LocalCents.Tracking` API from its own process, and nothing in the test can hand
it a directory — use `LocalCents.ProcessConfig`.

Production reads the setting from the application env as usual. In the test build,
`get/2` first looks the key up in the calling process's tree (its own dictionary,
its `$callers`, its ancestors) and only falls back to the application env when no
process in that tree has claimed a value:

```elixir
# In the test's setup — claims the value for this test and everything it spawns:
ProcessConfig.put(:books_dir, dir)

# In production code, anywhere the test reaches:
ProcessConfig.get(:books_dir)
```

The claim reaches further than it looks. `Phoenix.LiveViewTest` passes the test
pid as a `"caller"` join param and LiveView writes it into the view's process
dictionary, so a LiveView under `PhoenixTest` resolves the claim made by the test
that drives it — and so does a `Task` that LiveView spawns, because `Task`
prepends to `$callers` as it goes. Two tests running at once each resolve their
own value.

`LocalCents.BooksDirHelper` is the worked example: a feature test tags
`@moduletag :tmp_dir` and adds `setup :with_async_books_dir`, which claims that
directory for the test's process tree. Same directory the unit tests get — only
the way it reaches the code differs.

### 3. Swap the component, don't isolate the state

Sometimes the cheapest answer is a test-local implementation rather than a
test-local value. Oban's suite runs 35 of 35 modules async partly by substituting
an isolated peer and notifier for the ones that coordinate globally. If you find
yourself scoping a setting whose only job is to switch off a subsystem, consider
whether the subsystem should be swappable instead.

### The exception that stays

There is no rule against `async: false`; there is a rule against reaching for it
before the three above. A genuinely node-wide mutation with no seam — the ExUnit
docs' own example is `File.cd/1` — is a legitimate synchronous module. Say why in
a comment on the `use` line, naming the cell, so the next reader can tell a
considered decision from an unexamined one.

## Two sharp edges

A claim lives in a process dictionary. Both traps below are the same fact seen
from different sides, and neither announces itself — a missed claim silently
resolves to the application-env fallback rather than raising.

### Claim in `setup`, never in `setup_all`

`setup_all` runs in **its own process**, which is not an ancestor of any test
process. A claim made there is invisible to every test in the module:

```elixir
setup_all do
  ProcessConfig.put(:books_dir, dir)   # resolves to the fallback in every test
  :ok
end

setup do
  ProcessConfig.put(:books_dir, dir)   # correct — this runs in the test process
  :ok
end
```

The same reasoning rules out `on_exit`, which also runs in a separate process:
anything keyed to `self()` resolves differently there. Close over the value
instead — bind it in the setup body and let the callback capture it, rather than
calling `ProcessConfig.get/2` inside the callback and getting the fallback.

### Don't abandon work you started

A claim dies with the test process. **A process still working after the test
returns can no longer resolve it** and falls back to the application env.

This is not hypothetical. The Library window seeds a demo library in a task
spawned by `start_async`. One test asserted the loading state and then returned
while that task was still running, so the task wrote its Books into the shared
fallback directory a beat later — by then the test process it would have resolved
through was gone. The fix is to wait for the work to settle before the test ends:

```elixir
conn
|> visit(~p"/library")
|> assert_has("[role='status']", text: "Setting up your demo library")
|> refute_has("[role='status']", timeout: 10_000)
```

This is the known limit of a process-tree lookup, and the reason ownership-server
libraries like `nimble_ownership` exist: they hold the resource outside the test
process so it can still be resolved (and asserted on) after that process exits. We
do not need that yet — nothing we scope has to be readable once the test is over.

A related shape worth knowing: `LocalCents.Tracking.BookServer` processes are
supervised by the application, not by the test, so they outlive the test that
opened a Book. They are safe because each one is handed its directory as a
`start_link` argument and holds it in state — the one process a process-tree walk
could not reach is also the one that does not need reaching. Keep it that way.

## Two settings that read oddly on purpose

`config/test.exs` carries two settings whose shape is driven by this standard.

**The primary Logger level is `:debug` while the default handler stays at
`:warning`.** `ExUnit.CaptureLog` cannot see a message the primary level already
filtered, so a test asserting on a debug log would otherwise have to lift the
level at runtime — a node-wide mutation whose behavior ExUnit explicitly documents
as undetermined under async, and which `Jump.CredoChecks.AvoidLoggerConfigureInTest`
already flags. Splitting the two lets the capture see everything while the console
prints what it always did.

There is a consequence to know about. `ExUnit.CaptureLog` is **global**, not
scoped to the capturing process: every active capture receives every event that
clears the primary level, whatever process emitted it. Raising that level to
`:debug` therefore widens what a concurrent capture sees, so an assertion of the
form `refute log =~ …`, or an exact match on the whole captured string, can go red
at some seeds when an unrelated module logs at the same moment. Assert that the
message you expect is *present* and the problem does not arise.

**`:books_dir` still has an application-env value.** It is a backstop, not a
directory tests are expected to use: without it `BookStore.default_dir/0` falls
through to the real per-user application-support location, so a test that reached
the books directory without claiming one would enumerate and create the
developer's actual library. The path is keyed by OS pid, so two runs — two
worktrees, say — never share it. Nothing should ever land in it; if something
does, `test/test_helper.exs` says so on stderr when the suite finishes rather than
quietly deleting the evidence.

## Checklist for a new test module

- Start at `async: true`. Only drop it after you have named the shared cell and
  ruled out all three options above.
- Need a books directory? `@moduletag :tmp_dir` either way — pass it explicitly
  in unit and context tests, or add `setup :with_async_books_dir` to claim it in
  feature tests.
- Claim settings in `setup`, not `setup_all`.
- Do not call `Application.put_env/3` in a test. It is the mutation this whole
  guide exists to avoid, and it is the one thing that will make a passing suite
  fail for someone else at a different seed.
- If your test starts background work, make it wait for that work to finish.
