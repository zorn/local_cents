# Book Runtime Architecture

How an open **Book** lives at runtime: the processes that own its data, how they
are supervised, and how a change travels from a LiveView to disk and back out to
every viewer.

This is the *process* view. For the compile-time module/boundary view see
[Module Boundaries](module-boundaries.html); for the decision behind it see
[ADR 0007 — Book Runtime and Persistence](0007-book-runtime-and-persistence.html).

## The one-paragraph model

A Book is persisted as a single Automerge document in a `.lcbook` file. While a Book
is **open**, one `LocalCents.Tracking.BookServer` process holds that document in
memory and is the *single source of truth* for it. LiveViews never hold Book state;
they **subscribe** to the Book over `Phoenix.PubSub` and send **commands** to its
process. The process **persists each change first and, only once it is on disk,
commits it in memory and broadcasts** so every subscriber re-renders; a failed write
is returned to the caller rather than silently dropped. This is what lets several
viewers share one Book without divergence — the property the future web version
needs.

## Supervision tree

The tracking context owns its own runtime subtree, `LocalCents.Tracking.Supervisor`,
started once by `LocalCents.Application`. It supervises a **registry** (id → process
lookup) and a **dynamic supervisor** under which one `BookServer` is started per open
Book, on demand.

```mermaid
graph TD
    App["LocalCents.Application<br/><small>Supervisor, :one_for_one</small>"]

    Tel["LocalCentsWeb.Telemetry"]
    PS["Phoenix.PubSub<br/><small>name: LocalCents.PubSub</small>"]
    EK["ElixirKit.PubSub<br/><small>Rust/Tauri bridge</small>"]
    EP["LocalCentsWeb.Endpoint"]

    TS["LocalCents.Tracking.Supervisor<br/><small>Supervisor, :one_for_one</small>"]
    Reg["LocalCents.Tracking.BookRegistry<br/><small>Registry, :unique</small>"]
    DS["LocalCents.Tracking.BookSupervisor<br/><small>DynamicSupervisor, :one_for_one</small>"]

    BS1["BookServer<br/><small>one open Book</small>"]
    BS2["BookServer<br/><small>one open Book</small>"]

    App --> Tel
    App --> PS
    App --> TS
    App --> EK
    App --> EP

    TS --> Reg
    TS --> DS

    DS -.->|started on open| BS1
    DS -.->|started on open| BS2

    BS1 -.->|registers id| Reg
    BS2 -.->|registers id| Reg
```

> The `BookServer` children are **transient at the tree level**: none exist until a
> Book is opened, and in the MVP each stays resident until explicitly closed. Only
> Books actually open on screen consume a process. (Solid edges are static children;
> dashed edges are created at runtime.)

### Who's who

| Process | Kind | Role |
|---|---|---|
| `LocalCents.Tracking.Supervisor` | `Supervisor` (named) | Roots the context's runtime; boots the registry and dynamic supervisor. |
| `LocalCents.Tracking.BookRegistry` | `Registry`, `:unique` (named) | Maps a Book **id → BookServer pid** so callers reach a Book's process by id. |
| `LocalCents.Tracking.BookSupervisor` | `DynamicSupervisor` (named) | Starts/stops one `BookServer` per open Book. |
| `LocalCents.Tracking.BookServer` | `GenServer` (one per open Book) | Owns the in-memory Automerge document; applies commands, persists, broadcasts. |

## Data flow of a change

Everything a viewer does routes through the `LocalCents.Tracking` public API, which
forwards to the Book's process. The process is the only thing that touches the
Automerge document (`ExAutomerge`) and the file (`BookStore`).

```mermaid
graph LR
    LV["LiveView<br/><small>a viewer</small>"]
    API["LocalCents.Tracking<br/><small>public API</small>"]
    BSrv["BookServer<br/><small>owns the document</small>"]
    Auto["ExAutomerge<br/><small>Rust NIF, CRDT ops</small>"]
    Store["BookStore<br/><small>.lcbook file I/O</small>"]
    PS["Phoenix.PubSub<br/><small>topic book:ID</small>"]

    LV -->|command| API
    API -->|GenServer.call| BSrv
    BSrv -->|apply change| Auto
    BSrv -->|persist| Store
    BSrv -->|broadcast| PS
    PS -->|re-render| LV
```

### Sequence: adding an expense

```mermaid
sequenceDiagram
    participant LV as LiveView viewer
    participant T as LocalCents.Tracking
    participant BS as BookServer
    participant EA as ExAutomerge NIF
    participant St as BookStore
    participant PS as Phoenix.PubSub

    Note over LV: already subscribed to topic book:ID
    LV->>T: add_expense(id, %Expense{...})
    T->>BS: GenServer.call({:add_expense, desc, amount})
    BS->>EA: add_expense(doc, desc, amount)
    EA-->>BS: new document bytes
    BS->>St: save(id, new bytes)
    alt write succeeds (persist-then-commit)
        St-->>BS: :ok
        BS->>BS: commit new doc to state
        BS->>PS: broadcast(book:ID, {:book_updated, id})
        BS-->>T: :ok
        T-->>LV: :ok
        PS-->>LV: {:book_updated, id}
        Note over LV: re-reads via list_expenses(id) and re-renders
    else write fails
        St-->>BS: {:error, reason}
        Note over BS: state unchanged, no broadcast
        BS-->>T: {:error, reason}
        T-->>LV: {:error, reason}
    end
```

### Sequence: opening (or creating) a Book

`open_book/1` is idempotent — if the process is already running it is reused,
otherwise the dynamic supervisor starts one, which loads the document from disk.

```mermaid
sequenceDiagram
    participant T as LocalCents.Tracking
    participant DS as BookSupervisor
    participant BS as BookServer
    participant St as BookStore

    T->>DS: start_child({BookServer, id})
    alt not yet running
        DS->>BS: start_link(id)
        BS->>BS: Process.set_label({:book_server, id})
        BS->>St: load(id)
        St-->>BS: {:ok, document bytes}
        BS-->>DS: {:ok, pid} and registers id in BookRegistry
    else already running
        DS-->>T: {:error, {:already_started, pid}}
        Note over T: treated as {:ok, pid}
    end
```

## Finding processes in Erlang tooling

Two things make the runtime easy to browse in `:observer`, `:recon`, and crash logs:

- **Named infrastructure.** `Tracking.Supervisor`, `BookRegistry`, and
  `BookSupervisor` are registered under their module names, so they appear by name.
- **Labeled `BookServer`s.** A `BookServer` is registered through a `:via` tuple, so
  without help it would show only a bare pid. Its `init/1` calls
  `Process.set_label({:book_server, id})`, so tooling lists it by Book id instead.

```elixir
# In init/1 — makes the process identifiable by Book id.
Process.set_label({:book_server, id})
```

To confirm a label at runtime:

```elixir
[{pid, _}] = Registry.lookup(LocalCents.Tracking.BookRegistry, book_id)
:proc_lib.get_label(pid)
#=> {:book_server, "826f8d53-5036-459e-b4b1-c25695803164"}
```

In `:observer`'s process list the **Label** column shows `{:book_server, <id>}` for
each open Book, so you can tell at a glance which Books are resident.

## Lifecycle (interim)

A `BookServer` starts when a Book is opened, persists on **every** change, and — in
the MVP — **stays resident until explicitly closed** (`Tracking.close_book/1`) or the
application shuts down.

```mermaid
stateDiagram-v2
    [*] --> Resident: open_book or create_book
    Resident --> Resident: command, persist, broadcast
    Resident --> [*]: close_book, then stop
```

ADR 0007 ultimately calls for the process to persist once more and stop when the
**last viewer disconnects** (auto-shutdown-on-last-viewer). That requires monitoring
subscriber presence and is only meaningfully testable against real viewers, so it is
deferred until the windows/LiveViews that create those subscribers exist —
tracked in [#74](https://github.com/zorn/local_cents/issues/74).

## Persistence at a glance

- One Automerge document per Book, saved as `<book-id>.lcbook` in the books directory
  (see [ADR 0009](0009-book-file-format.html)). The **library is the enumeration of
  that directory**.
- The Book **id** is the file name (a UUID); the human-readable **name** lives inside
  the document and is read back with `ExAutomerge.document_name/1`.
- `BookStore.path/1` validates that an id is a single safe path component before any
  file operation, so an id arriving later from a `/books/:id` route param cannot
  traverse out of the books directory.
