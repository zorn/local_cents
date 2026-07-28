# Inspecting a Running App

How to attach Erlang's **observer** — or the lighter **LiveDashboard** — to the BEAM
that `cargo tauri dev` spawns, so you can watch the live supervision tree and confirm
process lifecycle behavior by eye. This is the tool-side companion to
[Book Runtime Architecture](book-runtime-architecture.html) (what the tree *should*
look like) and [Book Runtime Lifecycle](book-runtime-lifecycle.html) (when a
`LocalCents.Tracking.BookServer` starts and reaps).

Reach for this when a test tells you *that* something happened but you want to see
*where* — auto-shutdown, supervision restarts, a process that outlives its window.

## The quick option: LiveDashboard

No relaunch needed. With `cargo tauri dev` already running, open
**<http://127.0.0.1:4000/dev/dashboard>** in Safari or Chrome. The dev routes are
already mounted in `LocalCentsWeb.Router`. The **Applications** page renders the
supervision tree; the **Processes** page lists live pids.

> #### Don't open a Book in the external browser {: .warning}
>
> Visiting a `/books/:id` URL in that browser mounts a real document LiveView, which
> calls `LocalCents.Tracking.register_viewer/1` and therefore counts as a **viewer**.
> That silently keeps the Book resident and invalidates any last-viewer shutdown you
> are trying to observe. Keep the browser on `/dev/dashboard` and drive all Book
> opening and closing through the Tauri windows.

## The full option: Erlang observer

Observer gives you what LiveDashboard can't: per-process state, message queues, links
and monitors, ETS contents, and a tracing UI.

### 1. Relaunch the app with distribution enabled

The dev BEAM is **not distributed by default**. `elixir_command/1` in
`tauri/src/lib.rs` runs a bare `elixirkit::mix("phx.server", &[])` with no node name
and no cookie, so there is nothing for observer to attach to.

Tauri's spawned child inherits the environment, so naming the node is just a matter of
launching with `ELIXIR_ERL_OPTIONS` set:

```fish
env ELIXIR_ERL_OPTIONS="-sname localcents -setcookie localcents" cargo tauri dev
```

The value takes **`erl` flags**, not `elixir` flags — `-sname`, not `--sname`.

### 2. Start observer from your own node

In a second terminal, start a separate node and drive observer from there:

```fish
iex --sname obs --cookie localcents
```

```elixir
Node.connect(:"localcents@YourHostname")   # required before observer will list it
:observer.start()
```

Then use **Nodes → localcents@YourHostname**, and the **Applications** tab →
`local_cents`.

Running observer from your own node is deliberate. If you instead `--remsh` into the
app's node and call `:observer.start()` there, the wx window is owned by the
Tauri-spawned child process, which is not a foreground GUI application — the window
may fail to appear or fail to take focus.

Two prerequisites, both usually already true: Erlang must be built with `wx`
(check with `erl -noshell -eval 'io:format("~p~n",[code:lib_dir(wx)]),halt().'`), and
`-sname` requires a resolvable short hostname.

### 3. Shorten the grace period

`LocalCents.Tracking.BookServer` lingers for `viewer_grace_ms` (60 seconds in dev, see
`config/config.exs`) after its last viewer disconnects. That's a long time to sit
watching a tree. The value is read at **arm time**, not at boot, so you can shrink it
on the live node without a restart:

```elixir
:rpc.call(:"localcents@YourHostname", Application, :put_env, [
  :local_cents, LocalCents.Tracking.BookServer, [viewer_grace_ms: 5_000]
])
```

## Reading the Applications tab

Two things about this UI cause more confusion than anything else in it.

### It is a static snapshot

The tree **does not auto-refresh**. It is rendered once when you select the
application and never redrawn on its own. Select a different app in the left-hand list
and select `local_cents` again to force a redraw.

This is the single easiest way to talk yourself into a bug that isn't there: you close
a document window, look at a stale canvas, and conclude the `BookServer` never shut
down. Always redraw before judging.

### Blue lines are secondary links

The tree is built by crawling **process links** breadth-first from the application
master — not by reading supervisor child specs. Each link found is classified
(`appmon_info.erl`, in `runtime_tools`):

| Line | Meaning |
|---|---|
| **Black** | A *primary* link. The child's `$ancestors` confirms this box is its real parent, so the link is drawn as a tree edge. |
| **Blue** | A *secondary* link. The two processes are linked, but the link is not the supervision edge that placed the box in the tree. |

A process is drawn in exactly one place, so every additional link it participates in
becomes a blue overlay line. Blue shows up when the child's `$ancestors` names a
different parent, when the process was already reached by another path, or when the
link crosses to another node. The classification is a heuristic — the source comment
says as much: *"Note that this part is pretty much a guess."*

Blue lines are drawn straight from box to box and cut across the whole canvas, so they
often appear to originate at whatever box they happen to pass near. To identify a real
endpoint, right-click a box → **Process info** → **Links**.

Blue lines are worth attention because a link means bidirectional exit-signal
propagation. For this codebase the load-bearing check is that a `BookServer` box has
**only** its black edge from `LocalCents.Tracking.BookSupervisor` and no blue link to a
LiveView. Viewers are coupled to the runtime through `LocalCents.Tracking.Presence`
monitors, not links, precisely so a crashing document window cannot cascade into the
Book's runtime.

## What to look for when reviewing the runtime lifecycle

With the tree redrawn after each step:

- **A Book opens** → a `{book_server, <<"…id…">>}` child appears under
  `LocalCents.Tracking.BookSupervisor`.
- **The last window closes** → after the grace period, that child is gone, and
  `Registry.lookup(LocalCents.Tracking.BookRegistry, id)` returns `[]`.
- **Close then reopen inside the grace period** → the pid is **unchanged**. The reap
  was cancelled, not completed and restarted. This is the whole point of the grace
  period.
- **Two windows on one Book, close one** → nothing arms; a reap is only scheduled when
  presence goes fully empty.
- **A second Book stays open throughout** → its server is untouched, which is the
  `:one_for_one` guarantee.
