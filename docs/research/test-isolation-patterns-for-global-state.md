# Test Isolation Patterns for Process-Wide Global State

> Research note feeding [issue #147](https://github.com/zorn/local_cents/issues/147) — the companion to [`avoiding-async-false-tests.md`](avoiding-async-false-tests.md), which settled the *unit/context* half of [issue #78](https://github.com/zorn/local_cents/issues/78) by injecting the books directory as an argument. That note stopped where the LiveView feature tests begin. This one surveys how the Elixir ecosystem isolates genuinely process-wide state, reads the mechanisms in source rather than in summary, and lands the survey back on our shape.
>
> Primary sources: the Elixir standard library and ExUnit as installed here (`~/.asdf/installs/elixir/1.20.2-otp-29/lib/ex_unit/lib/ex_unit/`), OTP's [`proc_lib.erl`](https://github.com/erlang/otp/blob/master/lib/stdlib/src/proc_lib.erl) (`~/.asdf/installs/erlang/29.0.4/lib/stdlib-8.0.3/src/proc_lib.erl`), the vendored source of `phoenix_ecto`, `phoenix_live_view`, `phoenix_test`, and `req` in `deps/`, plus the GitHub source of `ecto_sql`, `db_connection`, `nimble_ownership`, `mox`, `process_tree`, and oban-bg/oban at v2.23.0 (read as a checkout, not a summary). Elixir Forum threads and blog posts were used only to locate primary material and are marked where cited. Four experiments were run against this exact repo and toolchain (Elixir 1.20.2-otp-29 / Erlang 29.0.4) and are reported with their numbers.
>
> **Status:** research complete. Written against `main` at `c15aa26`; **applied** in [issue #147](https://github.com/zorn/local_cents/issues/147), which took Option B rather than the Option A recommended below — `$callers` resolution through `LocalCents.ProcessConfig`, backed by the `process_tree` library. The suite went to 339 tests, all `async: true`, 7.6s with an empty serial tail. The standard lives in the Testing section of `CODING_STANDARDS.md` and the seam in `LocalCents.ProcessConfig`; this note remains the evidence behind them and is not maintained against the code.

## The outcome, first

Three findings change the shape of issue #147.

1. **The premise of #147 is wrong.** `$callers` *does* reach a LiveView process in a `Phoenix.LiveViewTest` session — `Phoenix.LiveViewTest` passes the test pid as a `"caller"` join param and Phoenix.LiveView.Channel (`deps/phoenix_live_view/lib/phoenix_live_view/channel.ex`) writes it into the LiveView's process dictionary. Verified in this repo: the LiveView's `$callers` is `[test_pid]`. The Ecto-sandbox-style handshake #147 contemplates building is therefore *not* needed; the plain `$callers` lookup the companion note ruled out (as its "Option B") is available.
2. **The companion note overstates `$callers` in the other direction.** It says `$callers` is populated "for `Task`s and for `GenServer`/`proc_lib` children started directly by the caller." Only the `Task` half is true. `proc_lib` sets `$ancestors`, never `$callers`; a plain `GenServer.start_link/3` propagates nothing. Verified below.
3. **ExUnit has had a cheaper answer than `async: false` since v1.18: `group:`.** A module can be `async: true, group: :books_dir` — mutually exclusive with its group peers, fully concurrent with everything else. That is strictly better than `async: false`, needs no production change, and would move 16 seconds out of this suite's serial tail.

Measured on this repo today: `mix test` is **20.2s total = 4.1s async + 16.1s sync**. Six modules run serially and they account for 80% of the wall clock. The recommendation at the end lands both a same-day fix and the real one.

A fourth finding, added after the first pass: **Oban's own suite has no `async: false` in it at all** — 35 of 35 modules async, in a library with a database, supervised background processes, leader election, and pubsub. Its `test/support/case.ex` is the best worked example in the ecosystem of a suite that refused to go serial, and it solves the unreachable-process problem by inverting `$callers` rather than walking it. See the Oban section.

## 1. What ExUnit actually guarantees

### 1.1 The `async: true` contract is a single conditional sentence

`ExUnit.Case`'s option list (`case.ex:14`) is the whole rule:

> `:async` - configures tests in this module to run concurrently with tests in other modules. Tests in the same module never run concurrently (with the exception of tests run via the `:parameterize` option - see below). **It should be enabled only if tests do not change any global state.** Defaults to `false`.

The docs' own example of a legitimate "no" is a process-wide mutation, not a slow test (`case.ex:88`):

```elixir
defmodule FileTest do
  # Changing directory cannot be async
  use ExUnit.Case, async: false
```

Note the granularity: `async` is a module-level option. There is no per-test opt-out, which is why isolating a shared resource is what lets a whole module flip.

### 1.2 `async: false` is not "one module of wall clock" — it is a serial tail phase

This is the fact worth internalizing before deciding anything. `ExUnit.Runner.async_loop/4` (`runner.ex:104`) drains every async module first, hard-asserts that none are still running, and only then runs sync modules **one at a time**:

```elixir
true ->
  sync_modules = ExUnit.Server.take_sync_modules()
  modules_to_restore = maybe_store_modules(modules_to_restore, :sync, sync_modules)

  # Wait for all async modules
  0 =
    running
    |> Enum.reduce(running, fn _, acc -> wait_until_available(config, acc) end)
    |> map_size()

  # Run all sync modules directly
  for pair <- sync_modules do
    running = spawn_modules(config, [{nil, [pair]}], false, %{})
    running != %{} and wait_until_available(config, running)
  end
```

ExUnit.Server enforces the same ordering on its side (`server.ex:79`): `handle_call(:take_sync_modules, ...)` pattern-matches `%{waiting: nil, loaded: :done, async_groups: []}` and asserts `:queue.is_empty(state.async_modules)`. So N sync modules cost the *sum* of their runtimes, with zero overlap and no benefit from `max_cases`.

`:max_cases` only ever governs the async phase ([`ExUnit.configure/1`](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1), `ex_unit.ex:363`):

> `:max_cases` - maximum number of tests to run in parallel. Only tests from different modules run in parallel. It defaults to `System.schedulers_online * 2` to optimize both CPU-bound and IO-bound tests

On this machine that is 20, which is what the suite header reports.

### 1.3 `group:` — mutual exclusion without leaving the async phase

Added in v1.18 and aimed at exactly our situation (`case.ex:20`):

> `:group` (since v1.18.0) - configures the **group** this module belongs to. Tests in the same group never run concurrently. Tests from different groups (or with no groups) can run concurrently when `async: true` is given.

The [official v1.18 release announcement](https://elixir-lang.org/blog/2024/12/19/elixir-v1-18-0-released/) frames the motivation in words that describe LocalCents:

> While ExUnit supports running tests concurrently, those tests must not have shared state between them. However, in large applications, it may be common for some tests to depend on some shared state, and other tests to depend on a completely separate state. For example, part of your tests may depend on Cassandra, while others depend on Redis. Prior to Elixir v1.18, these tests could not run concurrently, but in v1.18 they might as long as they are assigned to different groups.

The mechanism is in `ExUnit.Server.take_modules/1` (`server.ex:157`), which hands out a group as a single `{group, modules}` pair, and `ExUnit.Runner.spawn_modules/4` (`runner.ex:168`), which runs that pair's modules sequentially inside **one** spawned slot:

```elixir
{pid, ref} =
  spawn_monitor(fn ->
    Enum.each(modules, fn {module, params} ->
      run_module(config, module, async?, group, params)
    end)
  end)
```

Two properties follow, and both matter. A grouped module is still `async: true`, so it never falls into the serial tail. And `group:` is inert on a sync module — `server.ex:140` matches `{:add, false = _async, _group, names}` and files it under `sync_modules` regardless.

**Verified.** Three modules each mutating one app-env key with a 120ms window, run with `--seed 0`:

| Configuration | Result | Phase timing |
|---|---|---|
| `async: true, group: :books_dir` | 4 passed | `0.3s async, 0.00s sync` |
| `async: true`, no group | **3 of 4 failed** — each observed a peer's value | `0.1s async, 0.00s sync` |

The grouped run also stayed entirely in the async phase alongside an ungrouped noise module, confirming that grouping costs concurrency only against the group.

### 1.4 Callback lifecycle: what is guaranteed to be torn down, and when

From [`ExUnit.Callbacks`](https://hexdocs.pm/ex_unit/ExUnit.Callbacks.html) (`callbacks.ex:35`), the documented order:

> 1. the test process is spawned
> 2. it runs `setup/2` callbacks
> 3. it runs the test itself
> 4. the test process exits with reason `:shutdown`
> 5. it stops all supervised processes synchronously
> 6. `on_exit/2` callbacks are executed in a separate process

and the guarantee that makes per-test processes a real isolation primitive:

> The advantage of starting a process under the test supervisor is that it is guaranteed to exit before the next test starts. Therefore, you don't need to remove the process at the end of your tests via `stop_supervised/1`.

> `setup_all` callbacks run in a separate process per module, while all `setup` callbacks run in the same process as the test itself. `on_exit/2` callbacks always run in a separate process, as implied by their name.

That last clause is a live hazard for any `$callers`-based scheme: an `on_exit` callback does **not** run in the test process, so anything keyed to `self()` resolves differently there.

There is also a primary-source correction to the intuition that `async: false` buys isolation. José Valim, on [elixir-lang/elixir#8892](https://github.com/elixir-lang/elixir/issues/8892) (core team, official tracker), on sync tests not waiting for linked processes:

> This is quite hard to guarantee in practice because processes can be linked and crashed at any time and there is no way ExUnit can intervene. If you want to guarantee a process terminates when the test terminates, then use `start_supervised`, to start the process in a tree managed by ExUnit or the `on_exit` callback.

In other words: if the reason a module is serial is leaked process state, `start_supervised` is the fix and the sync flag is not.

### 1.5 `:tmp_dir` is per-test isolation the framework already ships

`case.ex:285`:

> ExUnit automatically creates a temporary directory for tests tagged with `:tmp_dir` and puts the path to that directory into the test context. The directory is removed before being created to ensure we start with a blank slate.
>
> The temporary directory path is unique (includes the test module and test name) and thus appropriate for running tests concurrently.

The derivation lives in the runner, not the case module (`runner.ex:634`): an escaped module name, an escaped test name, and an eight-character truncated MD5 of `module <> "/" <> test_name <> parameters`, joined under `tmp/`. Worth knowing precisely, because it bounds the guarantee: the path is unique per *test*, not per *run*. Two concurrent runs in one working directory (two `--partitions` sharing a checkout) would collide on `File.rm_rf!` then `mkdir_p!` — see [elixir-lang/elixir#14190](https://github.com/elixir-lang/elixir/issues/14190).

LocalCents already uses this for the unit and context tests, which is what #78 delivered.

## 2. `$callers`, precisely: who sets it and who does not

`$callers` is Elixir's mechanism for "which process asked for this work," distinct from OTP's structural `$ancestors`. The [`Task`](https://hexdocs.pm/elixir/Task.html#module-ancestor-and-caller-tracking) docs define it (`task.ex:257`):

> The list of callers of the current process can be retrieved from the Process dictionary with `Process.get(:"$callers")`. This will return either `nil` or a list `[pid_n, ..., pid2, pid1]` with at least one entry where `pid_n` is the PID that called the current process…

**Only `Task` writes it.** Grepping the entire Elixir standard library for `:"$callers"` returns five hits, all in `task.ex`, `task/supervisor.ex`, and `task/supervised.ex`. Task.Supervised.noreply/3 (`task/supervised.ex:88`) does the write; Task.get_callers/1 (`task.ex:764`) does the accumulation, prepending the owner so chains compose:

```elixir
defp get_callers(owner) do
  case :erlang.get(:"$callers") do
    [_ | _] = list -> [owner | list]
    _ -> [owner]
  end
end
```

OTP's `proc_lib` — the substrate under every `GenServer`, `Agent`, and `Supervisor` — writes only `$ancestors` (`proc_lib.erl:326`):

```erlang
init_p(Parent, Ancestors, M, F, A) when is_atom(M), is_atom(F), is_list(A) ->
    put('$ancestors', [Parent|Ancestors]),
```

**Verified** on this toolchain, probing a `GenServer`'s process dictionary from `init/1`:

| How the process was started | `$callers` | `$ancestors` |
|---|---|---|
| `GenServer.start_link/3` directly from the test process | `nil` | `[test_pid]` |
| `GenServer.start_link/3` while the caller *has* `$callers` set | `nil` | `[caller_pid]` |
| `Task.async/1` | `[test_pid]` | `[test_pid]` |
| `DynamicSupervisor.start_child/2` | `nil` | `[dyn_sup, test_pid]` |
| `DynamicSupervisor.start_child/2` called from inside a `Task` | `nil` | `[dyn_sup, test_pid]` |

So the companion note's claim that `$callers` reaches `GenServer`/`proc_lib` children started directly by the caller is incorrect; its *conclusion* about our `BookServer` (a `DynamicSupervisor` child is unreachable via `$callers`) is right, for the `$ancestors` reason rather than the stated one. Note also that `$ancestors` for a `DynamicSupervisor` child does end at the test pid *only* when the supervisor itself was started by the test; LocalCents' `BookSupervisor` lives under the application tree, so in our suite it does not.

Libraries that consume `$callers` therefore all write their own ancestry walk, and — importantly — they do not agree on it:

- **`db_connection`** (Ecto's sandbox substrate) reads it at exactly one site, [`db_connection.ex:1351`](https://github.com/elixir-ecto/db_connection/blob/master/lib/db_connection.ex): `callers = [caller | Process.get(:"$callers") || []]`. Resolution is a linear scan in [`ownership/manager.ex`](https://github.com/elixir-ecto/db_connection/blob/master/lib/db_connection/ownership/manager.ex): `Enum.find(callers, &Map.has_key?(checkouts, &1)) || hd(callers)`.
- **Mox** falls back to OTP 25's `Process.info(pid, :parent)` when `$callers` is absent ([`mox.ex`](https://github.com/dashbitco/mox/blob/main/lib/mox.ex)): `case Process.get(:"$callers") do nil -> [self() | recursive_parents(self())]; pids when is_list(pids) -> pids end`. Note the either/or — if `$callers` is set, Mox never consults `:parent`.
- **`Req.Test`** concatenates all three (`deps/req/lib/req/test.ex:717`):

  ```elixir
  defp callers do
    Enum.concat([
      [self()],
      List.wrap(Process.get(:"$callers")),
      List.wrap(Process.get(:"$ancestors"))
    ])
  end
  ```

Three libraries, overlapping authors, one shared registry design, three different ancestry walks. That divergence is the signal: there is no canonical walk, and whoever adopts this pattern owns the choice.

## 3. `$callers` *does* reach a LiveView under test

This is the load-bearing correction. Phoenix.LiveView.Channel writes `$callers` on join (`deps/phoenix_live_view/lib/phoenix_live_view/channel.ex:1225`):

```elixir
case params do
  %{"caller" => {pid, _}} when is_pid(pid) -> Process.put(:"$callers", [pid])
  _ -> Process.put(:"$callers", [transport_pid])
end
```

That `"caller"` param is supplied by the test client, not by a browser. Phoenix.LiveViewTest.start_proxy/2 stamps `caller: {self(), ref}` (`deps/phoenix_live_view/lib/phoenix_live_view/test/live_view_test.ex:445`) and `ClientProxy` forwards it into the join payload (`deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex:277`):

```elixir
params = %{
  "session" => view.session_token,
  "static" => view.static_token,
  "params" => Map.put(view.connect_params, "_mounts", 0),
  "caller" => state.caller
}
```

Phoenix.Channel.Server does the same for classic channels (`deps/phoenix/lib/phoenix/channel/server.ex:303`).

**Verified in this repo.** A throwaway `ConnCase` test that mounts `/library` via `Phoenix.LiveViewTest.live/2` and reads the view's process dictionary with `:erlang.process_info(pid, :dictionary)`:

```
test pid:   #PID<0.564.0>
view pid:   #PID<0.568.0>
$callers:   [#PID<0.564.0>]
$ancestors: [#PID<0.565.0>, #PID<0.564.0>]
```

Both chains terminate at the test process — `$callers` directly, `$ancestors` because `ClientProxy` starts the channel under ExUnit's per-test supervisor (`test_supervisor: fetch_test_supervisor!()`, `live_view_test.ex:452`). `PhoenixTest` drives `Phoenix.LiveViewTest` (`deps/phoenix_test/lib/phoenix_test/live.ex:3`, `:35`), so our `FeatureCase` sessions inherit this unchanged. And because Task.get_callers/1 prepends, a `start_async`/`assign_async` task spawned by that LiveView carries `[view_pid, test_pid]`.

In production the same line assigns `[transport_pid]`, a process that owns nothing — so a `$callers`-keyed lookup degrades cleanly to its default outside tests.

What this does **not** reach: a process started under a long-lived application supervisor. Our `BookServer` is `DynamicSupervisor.start_child/2` under `LocalCents.Tracking.BookSupervisor` (`lib/local_cents/tracking/supervisor.ex`), so neither chain leads back to the test. That is the same wall Ecto hits, and the reason `allow/3` exists.

## 4. The Phoenix.Ecto sandbox handshake, as a mechanism you could copy

`Ecto.Adapters.SQL.Sandbox` is the ecosystem's reference answer to "one shared global resource, many concurrent tests." Its own summary of the design space is the clearest statement anywhere ([hexdocs](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html)):

> There are two mechanisms for explicit ownerships:
>
>   * Using allowances - requires explicit allowances. Tests may run concurrently.
>   * Using shared mode - does not require explicit allowances. Tests cannot run concurrently.

and, for the automatic path:

> Besides calling `allow/3` allowance can also be provided to processes via Caller Tracking.

The four moving parts, read from `deps/phoenix_ecto/lib/phoenix_ecto/sql/sandbox.ex`:

1. **An owner process per test.** `Ecto.Adapters.SQL.Sandbox.start_owner!/2` starts "a process that will check out and own a connection, then returns that process's pid." The canonical setup is one `start_owner!` plus one `stop_owner` in `on_exit`, with `shared: not tags[:async]` — the *same* setup serving async and sync modules, differing only in mode.
2. **A metadata channel that survives leaving the BEAM.** `metadata_for/3` builds `%{repo: …, owner: pid, trap_exit: true}`; `encode_metadata/1` does `:erlang.term_to_binary/1` → `Base.url_encode64/1` → `"BeamMetadata (…)"`. That string rides in an HTTP header — the `user-agent` by default (`init/1`: `header: Keyword.get(opts, :header, "user-agent")`).
3. **A plug that binds the request process.** The catch-all `call/2` clause is three lines:

   ```elixir
   def call(conn, %{header: header, sandbox: sandbox}) do
     header = extract_header(conn, header)
     allow(header, sandbox)
     assign(conn, :phoenix_ecto_sandbox, header)
   end
   ```

   `allow/2` decodes the metadata, optionally sets `trap_exit`, and calls `sandbox.allow(repo, owner, self())` — handing the *current* process the owner's connection.
4. **An `on_mount` that binds the LiveView process.** Because the LiveView is a different process from the request, the plug's binding does not carry. The documented hook re-reads the same header off the socket's connect info and re-allows:

   ```elixir
   def on_mount(:default, _params, _session, socket) do
     socket =
       assign_new(socket, :phoenix_ecto_sandbox, fn ->
         if connected?(socket), do: get_connect_info(socket, :user_agent)
       end)

     metadata = socket.assigns.phoenix_ecto_sandbox
     Phoenix.Ecto.SQL.Sandbox.allow(metadata, Ecto.Adapters.SQL.Sandbox)
     {:cont, socket}
   end
   ```

   The moduledoc is explicit that ordering matters — this hook must run before any `live_session` auth hooks so they can reach the database.

The generalizable shape, stated in the abstract: **an owner registry keyed by pid; a transport-independent encoding of "who owns this"; and one binding call at every process boundary the framework creates.** The header trick exists only because a browser or an external HTTP client cannot pass a pid. When the "client" is another BEAM process in the same node — which is our entire situation — `$callers` replaces the header and the whole encode/decode/plug/on_mount apparatus collapses to a lookup.

The mode toggle is the honest fallback. `mode(repo, {:shared, pid})` "makes it so all processes can use the same connection as the one owned by the current process. **This is the mode you will run your sync tests in**," and its cost is stated plainly: "The downside is that tests can no longer run concurrently in shared mode."

## 5. The pattern catalog

| Pattern | Named implementation | Isolation key | Reaches an app-supervised process? | Cost |
|---|---|---|---|---|
| Explicit dependency injection | LocalCents' own `:books_dir`/`:now`/`:today` options (`lib/local_cents/tracking.ex:592`) | the argument | Yes, if threaded to `start_link` | Wide API diff |
| Per-test temp directory | ExUnit `@tag :tmp_dir` (`runner.ex:634`) | module + test name hash | n/a (value, not lookup) | None; must still be injected |
| Per-test supervised process | `start_supervised!/2`, `start_link_supervised!/2` | the returned pid | Yes — it *is* the process | Only for state you can move into a process |
| `$callers` / `$ancestors` walk | [`ProcessTree`](https://github.com/jbsf2/process-tree) `get/2` | ancestry chain | **No** | Zero infrastructure; silent fallback on miss |
| Ownership registry | [`NimbleOwnership`](https://github.com/dashbitco/nimble_ownership) v1.0.2 | owner pid + key | Only via explicit `allow/4` | ~370 LOC or one dep |
| Telemetry ownership handoff | Oban's `attach_auto_allow/2` (see the Oban section below) | owner pid, granted at callee init | **Yes** — the callee announces itself | Callee must emit an init event |
| Mock ownership | [Mox](https://github.com/dashbitco/mox) private mode | owner pid | Only via `allow/3` | Requires a behaviour seam |
| Global-mode escape hatch | Mox `set_mox_global`, Ecto `{:shared, pid}` | none — one shared owner | Yes | Forces `async: false` |
| Serialize a subset | ExUnit `group:` (v1.18) | the group name | Yes — sidesteps the question | Group members serialize against each other |
| Serialize everything | `async: false` | none | Yes | The tail phase in the Options section above |
| Run in separate OS processes | `mix test --partitions` | the OS process | Yes | Per-partition setup; blind to test cost |

Notes on the ones worth reading rather than tabulating.

**`ProcessTree`** is the `$callers` idea packaged. `get/2` "recursively looks for a value for `key` in the process dictionaries of the calling process and its known ancestors/callers," giving priority to `parent`/`$ancestors` and falling back to `$callers`, and caching hits along the way. Its README pitches precisely our problem — "We need to work around our global data, for example by setting/resetting environment variables and using `async: false`" — and its `:default` option is designed as the app-env bridge: `ProcessTree.get(:some_key, default: Application.get_env(:my_app, :some_key))`. Its `known_ancestors/1` doc is candid that what is "known" depends on whether the ancestors are alive and how they were started, which is exactly where a `DynamicSupervisor` child under the application tree falls out of reach.

**`NimbleOwnership`** is *not* a caller-tracking library, and this is the most misunderstood thing about it. Its `allow/4` doc says so outright:

> The ownership server **does not** consider the direct and indirect "children" of a PID when determining who is allowed to access a key. […] Users of the server (and of this library) will usually want to call `fetch_owner/3` with a list of callers that generally can come from `Process.get(:"$callers", [])` or similar.

The whole resolution is nine lines of `Enum.find_value` over a list you supply. What it *does* own is the registry, the monitors that clean up when an owner dies, and the private/shared mode flag. Its private mode is the concurrent one; shared mode short-circuits resolution entirely, returning `{:shared_owner, pid}` "regardless of the `callers`."

**Mox** delegates its entire registry to NimbleOwnership (`{:nimble_ownership, "~> 1.0"}`) and keeps only the ancestry walk and the ergonomics. Its rule is enforced in code, not just documented:

```elixir
def set_mox_global(%{async: true}) do
  raise "Mox cannot be set to global mode when the ExUnit case is async. " <>
          "If you want to use Mox in global mode, remove \"async: true\" when using ExUnit.Case"
end
```

and `set_mox_from_context/1` is the two-line dispatcher worth stealing as a shape: `%{async: true} -> set_mox_private()`, otherwise `set_mox_global()`. One setup, correct in both modes, keyed off the ExUnit tag — the same shape as Ecto's `shared: not tags[:async]`.

**`Req.Test` vendors NimbleOwnership rather than depending on it**, and that precedent is already sitting in this repo. `deps/req/lib/req/test/ownership.ex` opens with:

```elixir
# Vendored from nimble_ownership v1.0.1, replacing NimbleOwnership.Error with
# Req.Test.OwnershipError.
#
# Check changes with:
#
#     git diff --no-index lib/req/test/ownership.ex ../nimble_ownership/lib/nimble_ownership.ex
```

368 lines, no dependencies of its own, with a one-line resync recipe in the header. Req's moduledoc is also the most honest statement in the ecosystem about where automatic resolution stops: it works "in many cases where the request happens in a spawned process, such as a `Task`, `GenServer`, and more," but a process spawned with raw `spawn/1` needs an explicit allowance, and the documented workaround for a worker pool is a Telemetry handler that calls `allow/3` at worker start.

**`Application.put_env` swapping** is the pattern we currently use and the one every primary source argues against. The [design anti-patterns](https://hexdocs.pm/elixir/design-anti-patterns.html#using-application-configuration-for-libraries) page states the underlying property — "the application environment is a **global** state, so there can only be a single value for each key in the environment for an application" — though, flagged honestly, **there is no official anti-patterns entry about global state in tests**; the async consequence is an inference from `ExUnit.Case`'s rule, not a quotation.

Also flagged honestly: **no statement by José Valim or another core team member endorsing `async: false` for integration tests could be found** on ElixirForum or the elixir-lang blog. The nearest official sanction is Ecto's sandbox doc calling it "a last resort" for deadlocks. The community-side corroboration ([ElixirForum: *How to test with application env in `async: true`*](https://elixirforum.com/t/how-to-async-tests-with-application-env/67222), [*Using `Application.get_env`/`put_env` in ExUnit tests*](https://elixirforum.com/t/using-application-get-env-application-put-env-in-exunit-tests/8019), and the [Bye Bye async: false](https://saltycrackers.dev/posts/bye-bye-async-false/) post) is *secondary* and adds no facts beyond the primary sources cited above.

## 6. Oban: a real suite with no `async: false` in it at all

The phoenix_ecto handshake in the Handshake section above is the canonical *library* mechanism. Oban is the canonical *worked example* of a whole suite that refuses to go serial, and it is the more useful model for us because Oban's problems are shaped like ours rather than like Ecto's.

Measured against oban-bg/oban at v2.23.0: **35 test modules, 35 of them `async: true`, zero `async: false`.** That is a job-processing library with a database, background worker processes started under its own supervision tree, cross-node leader election, and pubsub notification — every category of global state this note has been cataloging — and none of it forced a serial module. Nearly all of the machinery lives in one file, `test/support/case.ex`, which is worth reading end to end.

**One setup that is correct in both modes.** The `setup` block derives the sandbox's sharing mode from the test's own `:async` tag (`test/support/case.ex:33`, `:38`):

```elixir
pid = Sandbox.start_owner!(Repo, shared: not context[:async])
on_exit(fn -> Sandbox.stop_owner(pid) end)
```

This is the same shape as Mox's `set_mox_from_context/1` noted in the catalog above, and it is the detail that makes flipping a module to async a one-line change: nothing in the case template needs to know which mode it is in.

**A reference, not a registered name.** `start_supervised_oban!/1` defaults the instance name to `make_ref()` (`:49`), so each test gets its own Oban instance with no global atom to collide on. Naming is a category of shared global state that is easy to miss, and `make_ref/0` removes it outright.

**The telemetry ownership handoff — the idea worth stealing.** Oban has our exact unreachable-process problem: its engine, peer, and plugin processes start under Oban's own supervision tree, not under the test, so no ancestry walk from the worker will find the test pid. Rather than propagate callers, Oban **inverts the direction** (`:133-152`):

```elixir
auto_allow = fn _event, _measure, %{conf: conf}, {name, repo, test_pid} ->
  if conf.name == name, do: Sandbox.allow(repo, test_pid, self())
end

:telemetry.attach_many(
  telemetry_name,
  [
    [:oban, :engine, :init, :start],
    [:oban, :peer, :election, :start],
    [:oban, :plugin, :init]
  ],
  auto_allow,
  {name, repo, self()}
)
```

The test pid is captured in the handler config; each internal process announces itself by emitting an init event; the handler runs *in that process* and grants it ownership via `self()`. The `if conf.name == name` guard, combined with the `make_ref()` instance name, scopes the handler to this test's instance only, and `on_exit` detaches it.

This matters because it is a **general answer to "the process cannot be reached via `$callers`"** that does not depend on ancestry at all — which is notable given that, as the catalog above records, three separate Dashbit libraries disagree about how to walk that ancestry. Req's own docs point at the same technique for worker pools. The requirement it imposes is modest: the process must emit a telemetry event at init, carrying enough identity to tell whose it is.

**Isolated implementations of globally-coordinating components.** For the two things that genuinely coordinate across the system, Oban does not isolate the state — it swaps the component. `start_supervised_oban!/1` defaults `notifier: Oban.Notifiers.Isolated` and `peer: Oban.Peers.Isolated` (`:50-51`). The isolated peer is the whole idea in miniature: an `Agent` that defaults `leader?: true` (`lib/oban/peers/isolated.ex:10`), so every test's instance believes it is the leader and no election ever crosses test boundaries. Replacing a globally-coordinating implementation with a test-local one is cheaper than making the global one concurrent-safe.

**Retry-based assertions for genuinely async work.** `with_backoff/2` (`:66`) rescues `ExUnit.AssertionError` and retries on a sleep, defaulting to 100 attempts at 10ms. Worth knowing about as the honest alternative to sleeping a fixed interval, though it is orthogonal to isolation.

**What transfers.** The telemetry handoff is a genuine alternative to the `$callers` walk in Option B below, and a more robust one. We do not strictly need it — `BookServer` already takes its directory as a `start_link` argument, so the one process an ancestry walk could not reach is also the one that does not need reaching — but it is the right fallback if a future process ends up ambient and unreachable. The isolated-component pattern is the more immediately useful one: it is a concrete answer to the `:demo_seeding` global flagged in the Options section below, which neither Option A nor Option B addresses.

## 7. Keeping a suite fast when some of it must stay serial

Four documented levers, in descending leverage for us.

**Groups** (the Options section above). Strictly dominates `async: false` whenever a module is serial because of a *specific* resource rather than everything.

**OS-process partitioning** — the only mechanism that genuinely parallelizes sync modules, because each partition is an independent BEAM with its own async phase and its own serial tail ([`Mix.Tasks.Test`](https://hexdocs.pm/mix/Mix.Tasks.Test.html#module-operating-system-process-partitioning)):

> While ExUnit supports the ability to run tests concurrently within the same Elixir instance, it is not always possible to run all tests concurrently. For example, some tests may rely on global resources. For this reason, `mix test` supports partitioning the test files across different Elixir instances.

The mechanical caveat the prose understates: partitioning is by **file**, round-robin over a sorted list (`test.ex:1043`), so distribution is blind to test cost and a partition that collects several slow serial files will straggle. It also needs per-partition setup — the docs suggest keying it off `MIX_TEST_PARTITION` in `config/test.exs`, which for us would mean a per-partition books directory.

**Splitting the CI job by the `:async` tag.** `:async` is an automatically-set reserved tag (`case.ex:155`), so `--only async:true` / `--exclude async:true` partitions the suite with zero annotation. **Verified here:**

```
mix test --only async:true      → 4.2s  (258 passed, 69 excluded)
mix test --exclude async:true   → 16.5s (69 passed, 258 excluded)
```

Two parallel CI jobs at 4.2s and 16.5s instead of one at 20.2s. Cheap, but it optimizes CI rather than the local edit-test loop, and it does not shrink the 16.5s.

**Finding the bottleneck.** `--slowest-modules` (since v1.17) ranks modules by time including `setup`. The caveat to carry: it "Automatically sets `--trace` and `--preload-modules`," and `--trace` sets `max_cases: 1`, so the run is fully serial and the absolute numbers are not wall clock. Use it for ranking, not measurement.

## 8. What this means for LocalCents

### 8.1 The actual shape

Six modules are serial today, for two different reasons.

`test/local_cents_web/live_view_unhandled_info_test.exs` toggles the global Logger level under `ExUnit.CaptureLog`. That is a genuine process-wide mutation, it costs 0.05s, and it should stay as it is. It is the ExUnit `FileTest` case from the docs.

The other five all serialize on one thing — `LocalCents.BooksDirHelper` mutating `:books_dir` (`test/support/books_dir_helper.ex:25`) — and they are the entire cost:

| Module | Alone |
|---|---|
| `LocalCentsWeb.LibraryLiveTest` | 7.1s |
| `LocalCentsWeb.BookLiveTest` | 4.7s |
| `LocalCentsWeb.BookCategoriesLiveTest` | 3.6s |
| `LocalCentsWeb.BookReportLiveTest` | 1.2s |
| `LocalCentsWeb.BookWindowTest` | 0.05s |
| **All five, serialized** | **16.3s** |

Note #147 names three modules; there are five (`book_report_live_test.exs` and `book_window_test.exs` were added after it was filed).

The good news from #78 is that most of the work is already done. There is exactly **one** ambient read left, `lib/local_cents/tracking.ex:592`:

```elixir
defp opt_dir(opts), do: opts[:books_dir] || BookStore.default_dir()
```

Six `Tracking` entry points call it (`create_book`, `open_book`, `list_books`, `get_book`, `rename_book`, `delete_book`). Every one of them runs **in the caller's process** — the LiveView, or the test process during a dead render. `BookServer` never calls it: `ensure_started(id, dir)` receives the directory as an argument and holds it in state, so the one process `$callers` cannot reach is also the one process that does not need to be reached. That is the decisive fit finding.

### 8.2 The options, honestly

**Option A — `async: true, group: :books_dir` on the five modules.** Four one-line test-file edits, no production change, `BooksDirHelper` untouched. ExUnit guarantees the five never overlap, so the global mutation stays correct; they move out of the serial tail and overlap the 4.1s async phase. Estimated suite: **~16.4s, down from 20.2s** (19%). Two caveats, both real. First, `test/local_cents_web/plugs/content_security_policy_test.exs:62` is `async: true` and does a dead render of `/library`, which calls `Tracking.list_books()` and therefore reads `:books_dir` concurrently with the group — harmless for a CSP-header assertion (seeding is gated on `connected?/1`, `lib/local_cents_web/live/library_live.ex:53`), but it is a concurrent read of a mutating global and should either join the group or be noted. Second, this keeps a global mutation in the suite; it makes it *safe*, not *absent*.

**Option B — per-test ownership of the books directory, resolved via `$callers`.** A small owner registry maps a pid to a directory; `opt_dir/1` consults it by walking `[self() | $callers ++ $ancestors]` before falling back to the platform default. Section 3 establishes that this reaches every process that reads it. The five modules become fully `async: true` with no group, so they parallelize with each other; the suite floor becomes the longest single module. Estimated suite: **~7.5s** (63%). Keep the test-only code out of production by resolving the lookup module through `Application.compile_env/3` — a boot-time constant set once in `config/test.exs`, which is what the application environment is actually for, rather than a value mutated per test. Registration goes in a `setup` in `FeatureCase`, keyed to `self()`, with `NimbleOwnership`-style monitor cleanup rather than `on_exit` (recall from the Options section that `on_exit` runs in a *different* process, so a `self()`-keyed cleanup there would miss).

Two things Option B does not fix. `library_live_test.exs:191` also mutates `:demo_seeding`; under full async that becomes a second race, so that one module wants `group: :demo_seeding` (groups and ownership compose fine) — or, following Oban's isolated-component pattern from the Oban section above, a seeding implementation selected at compile time whose test version is inert, which removes the global rather than scheduling around it. And `BookServer` processes outlive the test that started them — they are app-supervised and keyed by UUID, so there is no cross-test collision, but a late `terminate/2` persist can write into a directory `on_exit` has already removed. That risk exists today; more concurrency makes it likelier. `Tracking.close_book/1` in the test teardown is the cheap mitigation.

**Option C — build the Ecto-style metadata handshake #147 describes.** A plug, an `on_mount`, header-encoded metadata. Given section 3, this is machinery for a problem we do not have: the header exists only because a browser cannot pass a pid, and our "client" is a process in the same node. **Do not build this.**

**Option D — accept `async: false` and write the decision note.** Defensible on the primary sources: ExUnit's rule is conditional, and Ecto treats sync mode as a legitimate configuration rather than a failure. But it is hard to justify *here*, because Option A costs four lines and is strictly better on every axis. Accepting serial is right when the state is truly node-wide (our Logger module); the books directory is not.

### 8.3 Recommendation

**Take Option A now, then decide on Option B against a measured baseline — and do not build Option C.**

Option A is four lines, has no production surface, and cannot be wrong: `group:` is a scheduling constraint enforced by ExUnit, so it either serializes the group or it does not, with no new failure mode. It also converts #147 from "accept or build machinery" into "we already stopped paying the tail-phase penalty," which is most of what the issue is actually about.

Option B is the correct end state and is now known to be *reachable*, which it was not when #147 was written — the `$callers` chain does reach a LiveView under `Phoenix.LiveViewTest`, and `BookServer` already takes its directory as an argument. It buys roughly nine seconds beyond Option A. The trade-off is honest: a resolver seam in the production directory-resolution path, an ownership registry to maintain (or `Req.Test`'s 368 vendored lines to copy, with the precedent already in `deps/`), and a `$callers` walk whose exact shape three separate Dashbit libraries disagree about. Nine seconds may or may not be worth that today; it will be worth more as the feature suite grows, and Option A does not foreclose it.

Either way, update `avoiding-async-false-tests.md`: its `$callers` claim about `GenServer`/`proc_lib` is wrong (section 2), and its Option B was ruled out partly on a premise that does not hold for LiveViews (section 3). *(Done — both are annotated inline in that note as of the PR carrying this one.)*

## 9. Further reading and viewing

Video on this topic is thin, and what exists is worth calibrating before spending an evening on it. Neither of these was watched in preparing this note; they are listed from their published descriptions.

[**$callers and $ancestors and Tasks oh my!**](https://www.youtube.com/watch?v=31W6OOVUGVs) — Isaac Yonemoto, published on his own channel around May 2022, not a conference recording. The closest thing to a talk about this note: the `$callers`/`$ancestors` mechanism, how it interacts with tasks, and using it to run async tests against the Ecto sandbox without race conditions. Described as code-heavy. Background on why the mechanism exists at all is in [elixir-lang/elixir#7995](https://github.com/elixir-lang/elixir/issues/7995), the proposal that added `$callers` in Elixir 1.8 explicitly so that "testing tools that rely on ownership mechanisms" could propagate without forcing tests to run synchronously — which is the whole subject of this note, stated by the feature's author before the feature existed.

[**Sustainable Testing**](https://www.youtube.com/watch?v=9XRe1ce5eak) — Andrew Bennett, ElixirConf 2018. Adjacent rather than on point: what makes a long-lived test suite effective at revealing bugs. Slides and sources at [potatosalad/elixirconf2018](https://github.com/potatosalad/elixirconf2018).

The better material is written. [Andrea Leopardi, *How to Async Tests in Elixir*](https://andrealeopardi.com/posts/async-tests-in-elixir/) and [DockYard, *Understanding Test Concurrency in Elixir*](https://dockyard.com/blog/2019/02/13/understanding-test-concurrency-in-elixir) cover the model; [AppSignal, *8 Common Causes of Flaky Tests in Elixir*](https://blog.appsignal.com/2021/12/21/eight-common-causes-of-flaky-tests-in-elixir.html) is the failure-mode catalog. All three are secondary sources and none of this note's factual claims rest on them.

But the single most useful thing to read is not prose at all: [`test/support/case.ex`](https://github.com/oban-bg/oban/blob/main/test/support/case.ex) in oban-bg/oban, about 160 lines, covered in the Oban section above.
