# Get-or-Start Under a `DynamicSupervisor` + `Registry`

> Research note feeding [PR #174](https://github.com/zorn/local_cents/pull/174) — `BookServer.ensure_started/2` grew a five-attempt retry loop with `Process.alive?/1` checks and `Process.sleep(2)` between attempts, on the theory that auto-shutdown makes stop/start churn routine and the `Registry` can therefore hand back a dead pid via `{:error, {:already_started, dead_pid}}`. The maintainer pushed back that this is "a lot of heavy machinery for what should have been a simple thing." This note tests that theory against the runtime's own source and against how the Elixir ecosystem actually writes get-or-start.
>
> Primary sources: the Elixir standard library source as installed here — [`Registry`](https://hexdocs.pm/elixir/Registry.html) (`~/.asdf/installs/elixir/1.20.2-otp-28/lib/elixir/lib/registry.ex`) and [`DynamicSupervisor`](https://hexdocs.pm/elixir/DynamicSupervisor.html) — plus OTP's [`gen.erl`](https://github.com/erlang/otp/blob/master/lib/stdlib/src/gen.erl) (`~/.asdf/installs/erlang/28.5.0.3/lib/stdlib-7.3/src/gen.erl`); the Mix/OTP guide's ["Dynamic supervisors"](https://hexdocs.pm/elixir/dynamic-supervisor.html) chapter; and the *source* (not documentation about the source) of Postgrex, Livebook, Commanded, Supabase Realtime, Swarm, Horde, Redix, Jido, Ash, Finch, esbuild, Swoosh, and Req. Vendored deps are cited by `path:line` in this repo. Two reproduction scripts (section 3) were run against this exact Elixir/OTP build.
>
> No forum or blog sources were needed: the runtime source settles the mechanism outright, and the ecosystem question is answered by reading the projects themselves. Where a project's own commit messages are cited, they are that project's primary record.
>
> **Status:** research complete, recommendation not yet applied. Written against the working tree of `book-runtime-auto-shutdown`.

## The two versions

On `main` (commit 28a423e), `lib/local_cents/tracking/book_server.ex`:

```elixir
def ensure_started(id, dir) do
  case DynamicSupervisor.start_child(@supervisor, {__MODULE__, {id, dir}}) do
    {:ok, pid} -> {:ok, pid}
    {:error, {:already_started, pid}} -> {:ok, pid}
    {:error, reason} -> {:error, reason}
  end
end
```

On the PR branch (`lib/local_cents/tracking/book_server.ex:92`–`:121`), the same function becomes a private arity-3 recursion with an attempt budget, a `cond` on `Process.alive?/1`, a `Process.sleep(2)` drain helper, and a fallback that returns `{:error, {:already_started, pid}}` when the budget runs out. The justification given in the `@doc` is that "the `Registry` clears a stopped server's entry asynchronously, so in the narrow window after a reap (or `close/1`) the supervisor can still answer `{:already_started, dead_pid}`."

That premise is the thing to test. It is false for Elixir's `Registry`.

## 1. What the runtime actually guarantees

### 1.1 `Registry` self-heals a stale unique entry at registration time

`Registry.register/3` for `:unique` keys does not simply fail when `:ets.insert_new/2` finds the key taken. It looks the incumbent up, checks whether it is alive, and — if it is not — deletes the entry and retries the registration (`registry.ex:1238`):

```elixir
defp register_key(:unique, key_ets, key, entry) do
  if :ets.insert_new(key_ets, entry) do
    :ok
  else
    # Note that we have to call register_key recursively
    # because we are always at odds of a race condition.
    case :ets.lookup(key_ets, key) do
      [{^key, {pid, _}} = current] ->
        if Process.alive?(pid) do
          {:error, {:already_registered, pid}}
        else
          :ets.delete_object(key_ets, current)
          register_key(:unique, key_ets, key, entry)
        end

      [] ->
        register_key(:unique, key_ets, key, entry)
    end
  end
end
```

The consequence is direct and load-bearing: **a leftover entry belonging to a dead process never blocks a new registration.** `{:error, {:already_registered, pid}}` — and therefore the `{:error, {:already_started, pid}}` that `GenServer.start_link/3` and `DynamicSupervisor.start_child/2` surface from it — is returned *only* when the holder passed `Process.alive?/1` inside `register_key/4`. The "registry hasn't drained yet, so I got a corpse" scenario the PR's `@doc` describes is precisely the scenario `register_key/4` already handles, one function call earlier and without sleeping.

This is not new behaviour to hedge against: this code is byte-for-byte identical from Elixir v1.4.0 (when `Registry` shipped) through v1.20.

### 1.2 The asynchronous cleanup is real — but it is a *lookup* problem, not a *start* problem

The `Registry` moduledoc is candid that cleanup lags (`registry.ex:169`):

> "Looking up, dispatching and registering are efficient and immediate at the cost of delayed unsubscription. For example, if a process crashes, its keys are automatically removed from the registry but the change may not propagate immediately. This means certain operations may return processes that are already dead."

The lag is genuine — cleanup runs in a partition process trapping `EXIT`. But the two read paths differ, and the difference is exactly the one that matters:

- **`Registry`'s `whereis_name/1`** (which is what `{:via, Registry, {reg, id}}` resolves through) filters: `if Process.alive?(pid), do: pid, else: :undefined` (`registry.ex:256`–`:272`).
- **`Registry.lookup/2`** does not filter. Its implementation (`registry.ex:673`–`:697`) contains no `Process.alive?/1` at all, and its `@doc` (`registry.ex:636`) says nothing about dead pids.

So the guard that *is* warranted goes on a `Registry.lookup/2` result — which is where LocalCents already, correctly, has one (`lib/local_cents/tracking/book_server.ex:129`–`:135`, `alive?/1`). It is not warranted on the pid inside `{:already_started, _}`, which came through `register_key/4`'s liveness check.

### 1.3 The docs' own prescription is "monitor, don't alive-check"

The paragraph immediately following the one quoted above is Elixir's stated position on this whole class of problem (`registry.ex:177`):

> "However, keep in mind those cases are typically not an issue. After all, a process referenced by a PID may crash at any time, including between getting the value from the registry and sending it a message. Many parts of the standard library are designed to cope with that, such as `Process.monitor/1` which will deliver the `:DOWN` message immediately if the monitored process is already dead and `send/2` which acts as a no-op for dead processes."

That is the general argument against an alive-check on any pid you are about to use: it is a time-of-check/time-of-use race. `Process.alive?/1` returning `true` does not mean the process is alive when your next message arrives. Section 3.2 shows this is not hypothetical here.

### 1.4 What the official get-or-start examples do

There is exactly one get-or-start example in the Elixir source, in the docs for `Registry.lock/3` (`registry.ex:715`):

```elixir
name = {:via, Registry, {MyApp.Registry, :key, :value}}

# Do not attempt to start if we are already running
if pid = GenServer.whereis(name) do
  pid
else
  case GenServer.start_link(__MODULE__, :ok, name: name) do
    {:ok, pid} -> pid
    {:error, {:already_started, pid}} -> pid
  end
end
```

Plain pass-through. Note the pre-check uses `GenServer.whereis/1` (which routes to the filtering `whereis_name/1`), not `Registry.lookup/2`.

The `DynamicSupervisor` moduledoc has no get-or-start example and no race acknowledgement; its `start_child/2` docs mention `{:error, {:already_started, pid}}` only to explain that it arises from name registration rather than from a duplicate child id. The Mix/OTP guide's ["Dynamic supervisors"](https://hexdocs.pm/elixir/dynamic-supervisor.html) chapter deliberately keeps create and lookup as separate functions and its test *asserts* the error rather than absorbing it. **No official Elixir documentation anywhere acknowledges a dead-entry race on the start path.**

### 1.5 The one shape that genuinely is unhandled: `{:already_started, :undefined}`

OTP builds the error term without consulting a type. `gen.erl:636`:

```erlang
register_name({via, Module, Name} = GN) ->
    case Module:register_name(Name, self()) of
	yes -> true;
	no  -> {false, where(GN)}
    end.
```

with `where({via, Module, Name}) -> Module:whereis_name(Name).` (`gen.erl:619`), and `gen.erl:196`:

```erlang
init_it(GenMod, Starter, Parent, Name, Mod, Args, Options) ->
    case register_name(Name) of
	true -> init_it2(...);
	{false, Pid} ->
	    proc_lib:init_fail(Starter, {error, {already_started, Pid}}, {exit, normal})
    end.
```

So the second element is whatever `Registry`'s `whereis_name/1` returns — and that returns `:undefined` when the holder is dead (`registry.ex:263`). Reaching `{:error, {:already_started, :undefined}}` requires the incumbent to be alive at `register_key/4`'s `Process.alive?/1` and dead microseconds later at `whereis_name/1`'s. Narrow, but reachable, and `GenServer`'s `@type on_start` is optimistic in claiming a `pid`.

This matters for the PR specifically: `Process.alive?(:undefined)` **raises** `ArgumentError` ("1st argument: not a pid"), verified against this build. The retry loop's `cond` would therefore crash the caller in the one situation it was written to survive. `main`'s version returns `{:ok, :undefined}` — also wrong, but the caller discards the value (section 4.3), so nothing observes it. Neither version is *right*; the defensive one is strictly worse in this case.

## 2. What the ecosystem does

Eighteen call sites were read, across fourteen third-party projects plus Elixir's own documentation. **Zero of them guard the pid in `{:error, {:already_started, pid}}` with `Process.alive?/1`. Zero of them sleep-and-retry the start on a local `Registry` conflict.** The idiom is unanimous.

Two near-misses, stated for honesty because neither is the pattern under review. Livebook's `apps/deployer.ex` recurses on `{:error, :already_started}` — but that is `:global` registration across a cluster, and the comment says so: "the global registration can still fail if the node joins the cluster while the app process is starting." Swarm's tracker sleeps 1s and retries — but only on a *remote* node's `{:error, {:noproc, _}}`, never on `already_registered`. Both are distributed-registration problems that Elixir's single-node `Registry` does not have.

| Project | Site | `already_started` handling | Self-terminates at runtime? |
|---|---|---|---|
| Elixir docs | `registry.ex:715` (`lock/3`) | plain `-> pid` | n/a |
| Elixir docs | Mix/OTP dynamic-supervisor chapter | not absorbed at all; asserted in a test | no |
| **Postgrex** | [`lib/postgrex/type_supervisor.ex`](https://github.com/elixir-ecto/postgrex/blob/master/lib/postgrex/type_supervisor.ex) | plain `-> pid`; `alive?` on the *lookup* only | **yes** — reap-after timeout on empty client set |
| **Livebook** | [`lib/livebook/utils/unique_task.ex`](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/utils/unique_task.ex) | plain `-> pid`, then `Process.monitor` | **yes** — `{:stop, :shutdown, …}` |
| **Livebook** | [`lib/livebook/apps/manager_watcher.ex`](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/apps/manager_watcher.ex) | plain `-> pid`, then `Process.monitor` | — |
| **Supabase Realtime** | [`lib/realtime/tenants/connect.ex`](https://github.com/supabase/realtime/blob/main/lib/realtime/tenants/connect.ex) | pid **discarded**; re-lookup via `get_status/1` | **yes** — idle-user shutdown |
| **Supabase Realtime** | [`lib/realtime/tenants/replication_connection.ex`](https://github.com/supabase/realtime/blob/main/lib/realtime/tenants/replication_connection.ex) | plain `-> {:ok, pid}` (twice) | **yes** — `:DOWN` on owner |
| **Commanded** | [`lib/commanded/aggregates/supervisor.ex`](https://github.com/commanded/commanded/blob/master/lib/commanded/aggregates/supervisor.ex) | pid **discarded**; returns the uuid | **yes** — `AggregateLifespan` idle timeout |
| **Commanded** | [`lib/commanded/registration/local_registry.ex`](https://github.com/commanded/commanded/blob/master/lib/commanded/registration/local_registry.ex) | plain `-> {:ok, pid}` | — |
| **Commanded EventStore** | [`lib/event_store/monitored_server.ex`](https://github.com/commanded/eventstore/blob/master/lib/event_store/monitored_server.ex) | pass-through, then `Process.monitor` | no |
| **Jido** | [`lib/jido/agent/instance_manager.ex`](https://github.com/agentjido/jido/blob/main/lib/jido/agent/instance_manager.ex) | plain `-> {:ok, pid}` ("Lost race"); `alive?` on the *lookup* | **yes** — idle timeout on last detach |
| **Redix** | [`lib/redix/cluster/manager.ex`](https://github.com/whatyouhide/redix/blob/main/lib/redix/cluster/manager.ex) | pass-through, then adopt via `Process.monitor` | — |
| **Swarm** | [`lib/swarm/registry.ex`](https://github.com/bitwalker/swarm/blob/master/lib/swarm/registry.ex) | plain `{:already_registered, pid} -> {:ok, pid}` | no |
| **Horde** | [`lib/horde/registry.ex`](https://github.com/derekkraan/horde/blob/master/lib/horde/registry.ex) | forwarded unchanged; liveness enforced inside `lookup/2` | no |
| **Ash** | `lib/ash/data_layer/ets/ets.ex` | pid discarded; re-derive from the table | no |
| **Finch** (vendored) | `deps/finch/lib/finch/pool/manager.ex:222` | pid discarded — `{:error, {:already_started, _}} -> :ok` | pools are on-demand |
| **Swoosh** (vendored) | `deps/swoosh/lib/swoosh/adapters/local/storage/manager.ex:31` | plain `-> pid`, then `Process.monitor` | — |
| **esbuild** (vendored) | `deps/esbuild/lib/esbuild.ex:191` | plain `-> pid`, then `Process.monitor` | **yes** — the task stops when done |
| **Req** (vendored) | `deps/req/lib/req/finch.ex:366` | pid discarded; returns the name | — |
| Broadway, Membrane | — | pattern not used at all | — |

Four of the vendored examples are readable without leaving this repo. Finch's carries the entire rationale in one comment:

```elixir
|> DynamicSupervisor.start_child(...)
# In case of races, it will return it has already been started
|> case do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end
```

esbuild's is the canonical monitor idiom in nine lines (`deps/esbuild/lib/esbuild.ex:191`):

```elixir
|> case do
  {:ok, pid} -> pid
  {:error, {:already_started, pid}} -> pid
end
|> Process.monitor()
```

### 2.1 Self-terminating processes are the *majority* of the survey, not an exception

This is the crux the PR turns on, so it is worth stating plainly. Postgrex type servers reap when their client set empties. Livebook sessions have `auto_shutdown_ms` — a no-clients inactivity period, the same design as this branch. Commanded aggregates stop on an `AggregateLifespan` timeout. Realtime tenant connections stop after eleven consecutive zero-user samples. Jido agents hibernate and stop on idle. Every one of them starts on demand through a registry name, and every one of them uses plain pass-through.

**Nobody treats self-termination as a reason to make the starter defensive.** Auto-shutdown does not change the calculus, because the mechanism that makes pass-through correct (section 1.1) has nothing to do with how often processes stop.

### 2.2 `{:already_started, :undefined}` in the wild

One project handles a non-pid, and it is instructive that it does not sleep. `commanded_horde_registry` (`lib/commanded/registration/horde_registry.ex`, unchanged since 2019):

```elixir
defp start(adapter_meta, name, func) do
  case func.() do
    {:error, {:already_started, nil}} ->
      case whereis_name(adapter_meta, name) do
        pid when is_pid(pid) -> {:ok, pid}
        _other -> {:error, :registered_but_dead}
      end

    {:error, {:already_started, pid}} when is_pid(pid) ->
      {:ok, pid}

    reply ->
      reply
  end
end
```

Note the shape: a `when is_pid(pid)` guard on the normal clause, one re-lookup for the abnormal one, and a **named error** (`:registered_but_dead`) rather than a retry budget. Also note the project: Horde, where the registry is distributed and stale entries genuinely do survive their holders. That is the setting where this defence earns its keep — and it still does not involve sleeping.

### 2.3 Nobody unregisters in `terminate/2` to avoid this

Searched for explicitly. `Registry.unregister/2` before dying appears in Finch's HTTP/2 pool (`lib/finch/http2/pool.ex`) and Commanded EventStore's `monitored_server.ex`, but in both cases against a *duplicate* registry used for routing, and for draining rather than to head off a start-time race. No project unregisters a `:via` name in `terminate/2` for this purpose. Given section 1.1, that would be redundant.

## 3. Reproduction against this Elixir/OTP build

Two scripts were run against Elixir 1.20.2-otp-28 / Erlang 28.5.0.3, modelling `BookServer`'s exact shape: `use GenServer, restart: :transient`, `{:via, Registry, {R, id}}` name, `DynamicSupervisor.start_child/2`.

### 3.1 The claimed race does not occur

20,000 iterations each of open → stop → immediate reopen, under `main`'s naive `ensure_started`:

| Scenario | Dead pids handed back |
|---|---|
| Synchronous `GenServer.stop/1` then immediate reopen (models `close/1`) | 0 / 20,000 |
| Async `{:stop, :normal, state}` then immediate reopen (models the reap) | 0 / 20,000 |
| Calling the returned pid after an async stop | 0 `:noproc`, 0 other exits / 20,000 |
| 8-way concurrent start of the same id, 2,000 rounds | every returned pid alive |

The naive version never once produced the corpse the PR is written to catch. That matches section 1.1 exactly: `register_key/4` evicted the stale entry and the new server registered.

### 3.2 The window that *is* real is one the retry loop cannot close

Change the model server to spend 20ms in `terminate/2` — which is what `BookServer` does, since `terminate/2` performs a final persist — and reopen 5ms into that window. Now the incumbent is genuinely alive-but-doomed, so `register_key/4` correctly reports `{:already_started, pid}`:

| Version | Calls on the returned pid that exited |
|---|---|
| naive (main) | 300 / 300 |
| defensive (the PR's alive-check + 5×2ms retry) | 300 / 300 |

Identical. `Process.alive?/1` returns `true` for a process inside `terminate/2`, so the guard passes the doomed pid straight through and the retry loop never runs. **The machinery adds no protection in the only window where the hazard exists**, which is the concrete form of the TOCTOU argument in section 1.3.

## 4. What to do instead — and whether LocalCents needs to do anything

Three established alternatives appear in the survey, in descending frequency.

### 4.1 Make the *use* site tolerant, not the *start* site defensive

Postgrex is the reference. `TypeServer.fetch/2` catches the exit and reports `:noproc`, and `Postgrex.Protocol.bootstrap/3` loops back through locate-or-start:

```elixir
case TypeServer.fetch(server) do
  {:lock, ref, types} -> ...
  :noproc -> bootstrap(s, status, buffer)   # retry the whole locate + fetch
  :error -> ...
end
```

Commanded arrived at the same place empirically, and its git history is the best evidence in the survey. Four commits — `f1fffc48` ("fix: reopen aggregate to execute command if it is stopped jut now"), `559ca6bc`, `b91d1fec` ("bugfix: retry command executing when the aggregator is down right before the execution"), `12beb62e` — progressively added `catch :exit, {:normal, …}` and `catch :exit, {:noproc, …}` clauses around a call made **through the `:via` name, never a cached pid**, plus a bounded (sleep-free) retry in the dispatcher. At no point was the fix `Process.alive?/1` on the start path; `Process.alive?` does not appear in Commanded's `lib/` at all.

### 4.2 `Process.monitor/1` instead of `Process.alive?/1`

Livebook, Redix, Swoosh, esbuild, and Commanded EventStore all take the pid unconditionally and immediately monitor it. Because `Process.monitor/1` delivers `:DOWN` with reason `:noproc` for an already-dead pid, the dead case folds into the normal path with no branch. Livebook's `unique_task.ex` treats `:noproc` as success outright.

### 4.3 Do not let the pid escape at all

Commanded's `open_aggregate/3` returns the aggregate uuid. Realtime's `connect/3` discards the pid and re-derives status. Req and Finch return the name. Ash re-wraps the table.

**LocalCents already does this, and it is the decisive fact for the PR.** Both callers throw the pid away:

- `lib/local_cents/tracking.ex:115` — `{:ok, _pid} <- BookServer.ensure_started(id, dir)`
- `lib/local_cents/tracking.ex:138` — `{:ok, _pid} -> :ok`

Every subsequent operation goes through `GenServer.call(via(id), …)` (`lib/local_cents/tracking/book_server.ex:144`, `:151`, and every command below), and `via/1` resolves through `Registry`'s `whereis_name/1`, which alive-filters (section 1.2). **No caller in this codebase ever touches the pid `ensure_started/2` returns.** The retry loop spends five attempts and up to 10ms of `Process.sleep` protecting a value that is immediately discarded at both call sites.

### 4.4 The residual risk, honestly stated

There *is* a narrow real hazard on this branch, and it is not the one the PR addresses: a viewer can reopen a Book while its server is inside `terminate/2` persisting, and the ensuing `Tracking.list_expenses/1` will exit `:noproc`. Section 3.2 shows neither version of `ensure_started/2` prevents this — the fix, if it is ever worth making, belongs at the call site per section 4.1, or is avoided entirely by keeping `terminate/2` cheap. The grace period (60s default) makes the window vanishingly small in practice: a viewer must arrive in the few milliseconds of a final disk write, a full minute after the last one left. This is worth a GitHub issue at most, not code today.

## Recommendation for LocalCents

**The maintainer's instinct is right. Revert `ensure_started/2` to `main`'s four-line shape.**

The reasoning, in order of weight:

1. **The stated premise is false.** `Registry.register/3` for `:unique` keys evicts a dead holder and retries before it will report a conflict (`registry.ex:1238`). `{:error, {:already_started, pid}}` from a `{:via, Registry, …}` start is only ever reported for a process that was alive at that check. There is no corpse to guard against. Twenty thousand close-then-reopen cycles produced zero (section 3.1).
2. **Where a hazard does exist, the machinery does not help.** A server inside `terminate/2` is alive by `Process.alive?/1`, so the guard passes the doomed pid through and the retry never fires — measurably identical to the naive version, 300/300 (section 3.2).
3. **It is strictly worse in the one edge case that is reachable.** `{:already_started, :undefined}` is constructible through `gen.erl:636`'s `{false, where(GN)}` path, and `Process.alive?(:undefined)` raises `ArgumentError`. The retry loop crashes where the simple version quietly returns a value nobody reads (section 1.5).
4. **The guarded value is discarded by every caller.** `lib/local_cents/tracking.ex:115` and `:138` both bind `_pid`; all real work goes through `via(id)` (section 4.3).
5. **The ecosystem is unanimous.** Eighteen get-or-start sites across fourteen projects plus Elixir's own docs, zero alive-checks on `already_started`, zero sleep-and-retry — including Postgrex, Livebook, Commanded, Realtime, and Jido, *all five of which have processes that stop themselves on idle or on last client* (section 2.1). Auto-shutdown is the normal case for this pattern, not the exceptional one.

Concretely:

- Restore `ensure_started/2` to `main`'s single public arity-2 clause; delete `ensure_started/3` and `ensure_started_after_drain/3`.
- Rewrite the `@doc` to state the guarantee rather than a defence. The working tree's current wording is already close to correct: registration checks the holder's liveness and evicts a dead entry, so `{:already_started, pid}` only ever names a live process. Cite `Registry`'s "Registrations" section so the next reader does not re-litigate it.
- **Keep `alive?/1`'s `Process.alive?` check** (`lib/local_cents/tracking/book_server.ex:129`). That one is correct and idiomatic — `Registry.lookup/2` genuinely does not filter dead pids (section 1.2), which is exactly the guard Postgrex and Jido place on *their* lookups. `GenServer.whereis(via(id)) != nil` would be an equivalent one-liner if a simplification is wanted; either is defensible.
- **Keep the regression test.** `test/local_cents/tracking/book_server_shutdown_test.exs` — "reopening right after closing yields a live, serving process" — asserts a real, valuable property. Revise its comment: it currently explains the behaviour by the dead-entry theory this note refutes. It passes because `Registry` self-heals, and it should say so.
- If the residual `terminate/2`-window risk (section 4.4) is judged worth tracking, open an issue for a call-site `:noproc` retry in the Postgrex/Commanded shape. Do not pre-emptively build it.

The third option — keeping some middle-ground defence, such as an `is_pid` guard on the match clause — is not worth taking. It would document a hazard the codebase cannot experience (the pid never escapes) at the cost of implying to future readers that the simple form is unsafe. The simple form is what Elixir's own documentation shows, what every surveyed project ships, and what this runtime makes correct.
