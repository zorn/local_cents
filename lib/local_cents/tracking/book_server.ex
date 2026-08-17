defmodule LocalCents.Tracking.BookServer do
  @moduledoc """
  The per-Book runtime process: one GenServer owns the in-memory Automerge
  document for a single *open* Book and is the single source of truth for it (see
  [ADR 0007](0007-book-runtime-and-persistence.html)).

  Every command (add expense, rename) computes the new document, **persists it
  through `LocalCents.Tracking.BookStore` first, and only then commits it to memory
  and broadcasts** on the Book's `Phoenix.PubSub` topic so that any subscribed
  LiveView re-renders. If the write fails the in-memory state is left untouched and
  the error is returned to the caller, so a failed save never silently loses a
  change. Book state deliberately never lives in a LiveView socket, which is what
  lets several viewers share one Book without divergence (needed for the future web
  version).

  Processes are registered by Book id in `LocalCents.Tracking.BookRegistry` and
  started under `LocalCents.Tracking.BookSupervisor`.

  ## Lifecycle

  A BookServer starts when a Book is opened and **auto-shuts-down once its last
  viewer disconnects** (ADR 0007). A *viewer* is a process that registered through
  `register_viewer/1` — a document-window LiveView — tracked in
  `LocalCents.Tracking.Presence` on the Book's `presence_topic/1`. The server watches
  that topic and, when a `presence_diff` leaves the viewer set empty, it arms a
  grace-period timer; if no viewer re-registers before it fires, the server stops
  `:normal` (persisting once more via `terminate/2`). A viewer re-registering cancels
  the pending reap — which is what keeps an in-window `push_navigate` between a Book's
  views (ADR 0017) from tearing the process down and reloading from disk.

  A Book that has **never** had a viewer (e.g. one created by `create_book/1` with no
  window, or a bare `open_book/1`) stays resident until `close/1` or app shutdown. That
  falls out of the topic scoping rather than any server-side bookkeeping: `presence_topic/1`
  is only ever tracked on by `register_viewer/1`, so a Book nobody viewed is never sent a
  diff and never wakes to reconcile. Because presence lives in a
  separate process, a crash-restarted server sees its still-open viewers via
  `Presence.list/1` at `init` and does not reap out from under them. The grace period
  is configurable (`config :local_cents, LocalCents.Tracking.BookServer,
  viewer_grace_ms:`); see `docs/book-runtime-lifecycle.md` for the full state machine.
  """

  # BookServer is the process shell that mirrors the entire Tracking context API, so
  # it legitimately depends on one type per domain concept (Book, Expense, Category)
  # on top of the process/registry/pubsub infrastructure. That breadth is inherent to
  # its coordinator role, not a smell to refactor away, so this module opts out of the
  # project-wide dependency cap rather than inflating it for every module.
  # credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies

  # `:transient` restart: a crash is recovered by the supervisor (the process
  # restarts and reloads the last persisted document), but an intentional
  # `close/1` — which stops with reason `:normal` — stays stopped. The default
  # `:permanent` would resurrect a just-closed Book, defeating `close/1`.
  use GenServer, restart: :transient

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.Presence
  alias LocalCents.Tracking.Report

  @registry LocalCents.Tracking.BookRegistry
  @supervisor LocalCents.Tracking.BookSupervisor

  # The extra signal category commands emit on top of `:book_updated`. It is additive
  # and coarse (noun-level, `{:categories_updated, book_id}`): a subscriber that only
  # cares about the Book's *category set* — e.g. the expense editor's picker — can
  # refresh on this and ignore the far more frequent `:book_updated` from expense
  # edits (see [ADR 0018](0018-category-assignment-through-the-editor.html)).
  @category_signals [:categories_updated]

  # Client

  @doc """
  Ensures a BookServer for `id` is running, starting it under the supervisor if
  needed. Returns the pid either way.

  `dir` is the books directory the server reads and writes the Book's `.lcbook`
  file in; it is stored in the server's state so the persistence path carries its
  own directory rather than reading a global (which is what lets the tracking
  tests run concurrently — see `docs/research/avoiding-async-false-tests.md`). It
  only takes effect when the server is first started: an already-running server
  keeps the directory it was started with.

  Auto-shutdown makes open/close churn routine, which raises the question of whether a
  reopen can be handed a just-stopped pid. It cannot: `Registry` registration for
  `:unique` keys checks the holder's liveness and evicts a dead entry before failing,
  so `{:already_started, pid}` is only ever reported for a live process. No liveness
  guard is needed here.
  """
  @spec ensure_started(Book.id(), dir :: String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(id, dir) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, {id, dir}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns true if a BookServer for `id` is currently running.

  The `Registry` clears entries for dead processes asynchronously, so a lookup can
  briefly still return a just-stopped pid; confirm liveness before answering.
  """
  @spec alive?(Book.id()) :: boolean()
  def alive?(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  @spec start_link({Book.id(), dir :: String.t()}) :: GenServer.on_start()
  def start_link({id, dir}) when is_binary(id) and is_binary(dir) do
    GenServer.start_link(__MODULE__, {id, dir}, name: via(id))
  end

  @doc "Returns the Book's name."
  @spec name(Book.id()) :: Book.name()
  def name(id), do: GenServer.call(via(id), :name)

  @doc """
  Returns the Book's library view — its name and `updated_at` in unix seconds — read
  from the in-memory document rather than from disk.

  The caller assembles the `Book` struct; this process holds the document, not the
  `updated_at` conversion (see `LocalCents.Tracking.register_viewer/1`).
  """
  @spec book_view(Book.id()) :: {Book.name(), seconds :: integer() | nil}
  def book_view(id), do: GenServer.call(via(id), :book_view)

  @doc """
  Returns the Book's expenses. The list order is not a contract callers should
  rely on (it is not stable across a CRDT merge); the view sorts for display.
  """
  @spec list_expenses(Book.id()) :: [Expense.t()]
  def list_expenses(id), do: GenServer.call(via(id), :list_expenses)

  @doc """
  Adds an expense built from `attrs`, persists, and broadcasts, returning the added
  Expense. `id` is the UUID assigned to the new Expense and `today` seeds a blank
  date (both injected by the caller). Returns a changeset error on invalid `attrs`,
  or another error if the write fails.

  `time` is the unix-seconds stamp recorded on the change so the Book's
  `updated_at` advances (see [ADR 0012](0012-book-last-updated-timestamp.html)).
  """
  @spec add_expense(
          Book.id(),
          attrs :: map(),
          Expense.id(),
          today :: Date.t(),
          time :: integer()
        ) ::
          {:ok, Expense.t()} | {:error, term()}
  def add_expense(id, attrs, expense_id, today, time) when is_binary(id) do
    GenServer.call(via(id), {:add_expense, attrs, expense_id, today, time})
  end

  @doc """
  Replaces the editable fields of the Expense `expense_id` with `attrs`, persists,
  and broadcasts, returning the updated Expense. Returns a changeset error on invalid
  `attrs`, a `:not_found` error for an unknown `expense_id`, or another error if the
  write fails.
  """
  @spec edit_expense(
          Book.id(),
          Expense.id(),
          attrs :: map(),
          today :: Date.t(),
          time :: integer()
        ) ::
          {:ok, Expense.t()} | {:error, term()}
  def edit_expense(id, expense_id, attrs, today, time) when is_binary(id) do
    GenServer.call(via(id), {:edit_expense, expense_id, attrs, today, time})
  end

  @doc """
  Hard-deletes the Expense `expense_id`, persists, and broadcasts. Returns a
  `:not_found` error for an unknown `expense_id`, or another error if the write fails.
  """
  @spec delete_expense(Book.id(), Expense.id(), time :: integer()) :: :ok | {:error, term()}
  def delete_expense(id, expense_id, time) when is_binary(id) do
    GenServer.call(via(id), {:delete_expense, expense_id, time})
  end

  @doc """
  Renames the Book, persists, and broadcasts. Returns an error if the write fails.

  `time` is the unix-seconds stamp recorded on the change so the Book's
  `updated_at` advances (see [ADR 0012](0012-book-last-updated-timestamp.html)).
  """
  @spec rename(Book.id(), Book.name(), time :: integer()) :: :ok | {:error, term()}
  def rename(id, new_name, time) when is_binary(id) do
    GenServer.call(via(id), {:rename, new_name, time})
  end

  @doc """
  Returns the Book's categories. The list order is not a contract callers should
  rely on (it is not stable across a CRDT merge); the view sorts for display.
  """
  @spec list_categories(Book.id()) :: [Category.t()]
  def list_categories(id), do: GenServer.call(via(id), :list_categories)

  @doc """
  Returns the Book's `Report` — its Category × Month spending matrix — for the given
  **Report range**, computed from the in-memory document so the whole matrix comes
  from one consistent snapshot. `range`/`now` are passed through to
  `LocalCents.Tracking.Report.compute/2`.
  """
  @spec report(Book.id(), Report.range(), now :: DateTime.t()) :: Report.t()
  def report(id, range, now), do: GenServer.call(via(id), {:report, range, now})

  @doc """
  Adds a category built from `attrs`, persists, and broadcasts, returning the added
  Category. `id` is the Book's id; `category_id` is the UUID assigned to the new
  Category (injected by the caller). Returns a changeset error on invalid `attrs`, or
  another error if the write fails.
  """
  @spec add_category(Book.id(), attrs :: map(), Category.id(), time :: integer()) ::
          {:ok, Category.t()} | {:error, term()}
  def add_category(id, attrs, category_id, time) when is_binary(id) do
    GenServer.call(via(id), {:add_category, attrs, category_id, time})
  end

  @doc """
  Renames the Category `category_id` from `attrs`, persists, and broadcasts,
  returning the updated Category. Returns a changeset error on invalid `attrs`, a
  `:not_found` error for an unknown `category_id`, or another error if the write
  fails.
  """
  @spec rename_category(Book.id(), Category.id(), attrs :: map(), time :: integer()) ::
          {:ok, Category.t()} | {:error, term()}
  def rename_category(id, category_id, attrs, time) when is_binary(id) do
    GenServer.call(via(id), {:rename_category, category_id, attrs, time})
  end

  @doc """
  Deletes the Category `category_id`, un-files its Expenses, persists, and
  broadcasts. Returns a `:not_found` error for an unknown `category_id`, or another
  error if the write fails.
  """
  @spec delete_category(Book.id(), Category.id(), time :: integer()) :: :ok | {:error, term()}
  def delete_category(id, category_id, time) when is_binary(id) do
    GenServer.call(via(id), {:delete_category, category_id, time})
  end

  @doc """
  Files the Expense `expense_id` under the Category `category_id`, persists, and
  broadcasts, returning the updated Expense. Returns an `:expense_not_found` or
  `:category_not_found` error when either is unknown, or another error if the write
  fails.
  """
  @spec assign_category(Book.id(), Expense.id(), Category.id(), time :: integer()) ::
          {:ok, Expense.t()} | {:error, term()}
  def assign_category(id, expense_id, category_id, time) when is_binary(id) do
    GenServer.call(via(id), {:assign_category, expense_id, category_id, time})
  end

  @doc """
  Un-files the Expense `expense_id` (nulls its `category_id`), persists, and
  broadcasts, returning the updated Expense. Returns an `:expense_not_found` error
  for an unknown `expense_id`, or another error if the write fails.
  """
  @spec unassign_category(Book.id(), Expense.id(), time :: integer()) ::
          {:ok, Expense.t()} | {:error, term()}
  def unassign_category(id, expense_id, time) when is_binary(id) do
    GenServer.call(via(id), {:unassign_category, expense_id, time})
  end

  @doc """
  Returns the next sync message this Book owes `peer`, or `nil` when there is nothing
  to send. Advances the server's per-peer sync state in place, creating one on first
  contact with a `peer`.

  The read half of a peer reconcile: the message carries only the changes `peer` is
  missing (ADR 0025). The caller delivers it to `peer`'s server via
  `receive_sync_message/3` and loops until both sides yield `nil`.
  """
  @spec generate_sync_message(Book.id(), peer()) :: binary() | nil
  def generate_sync_message(id, peer) when is_binary(id) do
    GenServer.call(via(id), {:generate_sync_message, peer})
  end

  @doc """
  Folds an inbound sync `message` from `peer` into this Book, persisting and
  broadcasting like any other change so open windows re-render the reconciled result.

  The write half of a peer reconcile. It records no new change time: the folded-in
  changes keep the stamps `peer` wrote them with, so the Book's `updated_at` reflects
  the latest edit across both peers rather than the moment of the sync (see
  [ADR 0012](0012-book-last-updated-timestamp.html)). Returns an error if the write
  fails, or if `message` is not a valid sync message.
  """
  @spec receive_sync_message(Book.id(), peer(), message :: binary()) :: :ok | {:error, term()}
  def receive_sync_message(id, peer, message) when is_binary(id) and is_binary(message) do
    GenServer.call(via(id), {:receive_sync_message, peer, message})
  end

  @doc """
  Returns the conflicts that peer reconciles have surfaced on this Book so far, as a
  `t:LocalCents.Tracking.BookDocument.conflict_summary/0`.

  The read behind the bell-and-badge signal: a view loads it on mount and refreshes it
  on `:book_updated`, so a conflicting sync lights the badge. Both lists are empty until
  a reconcile surfaces something. Held in memory only, so it starts empty each time the
  server starts.
  """
  @spec conflict_summary(Book.id()) :: BookDocument.conflict_summary()
  def conflict_summary(id) when is_binary(id) do
    GenServer.call(via(id), :conflict_summary)
  end

  @doc """
  Clears every conflict this session surfaced, returning the summary to empty, and
  broadcasts `:book_updated` so all windows re-read the now-quiet signal.

  The write behind the popup's "Dismiss all". Conflicts are in-memory session state, so
  this drops them without touching the document — nothing is persisted and no change time
  is recorded.
  """
  @spec dismiss_conflicts(Book.id()) :: :ok
  def dismiss_conflicts(id) when is_binary(id) do
    GenServer.call(via(id), :dismiss_conflicts)
  end

  @doc "Stops the process. The document is already persisted after every change."
  @spec close(Book.id()) :: :ok
  def close(id), do: GenServer.stop(via(id))

  @doc """
  Subscribes the calling process to the Book's change broadcasts.

  This module owns the Book's `Phoenix.PubSub` topic (see `topic/1`), so both
  subscribing and broadcasting live here rather than being hand-built by callers.
  """
  @spec subscribe(Book.id()) :: :ok | {:error, term()}
  def subscribe(id) when is_binary(id) do
    Phoenix.PubSub.subscribe(LocalCents.PubSub, topic(id))
  end

  @doc """
  Registers the calling process as a viewer of the Book, tracking it in
  `LocalCents.Tracking.Presence` on the Book's `presence_topic/1`.

  This is the counter to `subscribe/1`: subscribing is passive listening, while a
  tracked viewer is what keeps the runtime resident and, when the last one
  disconnects, triggers auto-shutdown (see the module's Lifecycle section). Presence
  monitors the caller, so its registration is dropped automatically when it dies —
  callers never explicitly unregister.
  """
  @spec register_viewer(Book.id()) :: {:ok, ref :: binary()} | {:error, term()}
  def register_viewer(id) when is_binary(id) do
    # Key each viewer by a string form of its pid so distinct viewers stay distinct
    # entries (two windows on one Book both count) — Presence keys are conventionally
    # strings. The server only inspects emptiness, but a per-pid key keeps the presence
    # list honest for any future "who's viewing" use.
    Presence.track(self(), presence_topic(id), inspect(self()), %{})
  end

  @doc """
  Broadcasts that the Book was deleted, so subscribers (e.g. an open document
  window) can react. Called after the file is removed, when no process remains to
  broadcast from within.
  """
  @spec broadcast_deleted(Book.id()) :: :ok | {:error, term()}
  def broadcast_deleted(id) when is_binary(id) do
    Phoenix.PubSub.broadcast(LocalCents.PubSub, topic(id), {:book_updated, id})
  end

  # Server

  # The GenServer state: the Book's id, its current encoded document bytes, and the
  # books directory it persists to (injected at start so the persistence path is not
  # coupled to a global — see `ensure_started/2`). Every command decodes `doc` into a
  # `BookDocument`, runs, and re-encodes.
  #
  # `reap_timer` is the pending auto-shutdown timer ref (or `nil`), armed when the
  # last viewer leaves and cancelled when one returns.
  #
  # `sync_states` holds one live per-peer sync state (see
  # `t:LocalCents.Tracking.BookDocument.sync_state/0`) for each remote peer this server
  # reconciles with, keyed by the caller's `peer` handle. It lives in memory only, so a
  # `close`/`open` drops it — which is honest reconnection behavior: a fresh link
  # starts a fresh exchange (ADR 0025).
  #
  # `conflicts` accumulates what peer reconciles surfaced (see
  # `BookDocument.accumulate_conflicts/2`), so callers have a source of truth for the
  # conflicts outstanding this session. In memory only, like `sync_states`: not persisted
  # state, dropped on a close or reap.
  @typep state() :: %{
           id: Book.id(),
           doc: binary(),
           dir: String.t(),
           reap_timer: reference() | nil,
           sync_states: %{peer() => BookDocument.sync_state()},
           conflicts: BookDocument.conflict_summary()
         }

  @typedoc """
  An opaque handle naming a remote peer this server syncs with. The caller (a future
  sync Channel, or a test driver standing in for one) picks it; the server only uses
  it to key the matching per-peer sync state.
  """
  @type peer() :: term()

  # A pure `BookDocument` command: given the decoded document it returns the new
  # document — with an optional result value (the created/updated Expense or
  # Category) — or an error.
  @typep command() ::
           (BookDocument.t() ->
              {:ok, BookDocument.t(), Expense.t() | Category.t()}
              | {:ok, BookDocument.t()}
              | {:error, term()})

  # What a command handler replies to the caller with: bare `:ok`, `{:ok, result}`
  # carrying the affected Expense/Category, or an error.
  @typep reply() :: :ok | {:ok, Expense.t() | Category.t()} | {:error, term()}

  @impl GenServer
  def init({id, dir}) do
    # Label the process so it's identifiable by Book id in `:observer` and other
    # Erlang tooling — otherwise a `:via`-registered process shows only its pid.
    Process.set_label({:book_server, id})

    with {:ok, doc} <- BookStore.load(dir, id),
         :ok <- validate_document(doc) do
      # Subscribe on the way up so no viewer join is missed. A crash-restart while a
      # window is still open is the case that matters: presence lives in its own
      # process, so those viewers survive our crash and are still tracked. We need no
      # snapshot of them here — the next diff reconciles against `Presence.list/1`, and
      # until one arrives there is nothing to reap.
      Phoenix.PubSub.subscribe(LocalCents.PubSub, presence_topic(id))

      {:ok,
       %{
         id: id,
         doc: doc,
         dir: dir,
         reap_timer: nil,
         sync_states: %{},
         conflicts: BookDocument.empty_conflict_summary()
       }}
    else
      {:error, :invalid_document} -> {:stop, {:invalid_document, id}}
      {:error, reason} -> {:stop, {:load_failed, reason}}
    end
  end

  # Confirm the loaded bytes are a valid Book document before the server starts
  # serving from them. A readable-but-corrupt or legacy `.lcbook` would otherwise
  # start fine and only blow up later on a `:name`/`:list_expenses` call — crashing
  # the server and exiting the caller. Fully decoding the document here exercises the
  # whole parse, so `open_book/1` fails deterministically instead.
  #
  # Any exception from `from_bytes/1` means the file is not a Book we can serve, so
  # rescue broadly: the Automerge NIF raises `ArgumentError` on bad bytes, but the
  # domain parse can also raise elsewhere — e.g. `Decimal.new/1` raises
  # `Decimal.Error` on a non-decimal cost string, which a narrower rescue would miss.
  defp validate_document(doc) do
    _ = BookDocument.from_bytes(doc)
    :ok
  rescue
    _exception -> {:error, :invalid_document}
  end

  @impl GenServer
  def handle_call(:name, _from, state) do
    {:reply, BookDocument.name(state.doc), state}
  end

  def handle_call(:book_view, _from, state) do
    {:reply, {BookDocument.name(state.doc), BookDocument.updated_at(state.doc)}, state}
  end

  def handle_call(:list_expenses, _from, state) do
    {:reply, BookDocument.expenses(decode(state)), state}
  end

  def handle_call({:add_expense, attrs, expense_id, today, time}, _from, state) do
    run(state, time, &BookDocument.add_expense(&1, attrs, expense_id, today))
  end

  def handle_call({:edit_expense, expense_id, attrs, today, time}, _from, state) do
    run(state, time, &BookDocument.edit_expense(&1, expense_id, attrs, today))
  end

  def handle_call({:delete_expense, expense_id, time}, _from, state) do
    run(state, time, &BookDocument.delete_expense(&1, expense_id))
  end

  def handle_call({:rename, new_name, time}, _from, state) do
    run(state, time, &BookDocument.rename(&1, new_name))
  end

  def handle_call(:list_categories, _from, state) do
    {:reply, BookDocument.categories(decode(state)), state}
  end

  def handle_call({:report, range, now}, _from, state) do
    {:reply, Report.compute(decode(state), range: range, now: now), state}
  end

  def handle_call({:add_category, attrs, category_id, time}, _from, state) do
    run(state, time, &BookDocument.add_category(&1, attrs, category_id), @category_signals)
  end

  def handle_call({:rename_category, category_id, attrs, time}, _from, state) do
    run(state, time, &BookDocument.rename_category(&1, category_id, attrs), @category_signals)
  end

  def handle_call({:delete_category, category_id, time}, _from, state) do
    run(state, time, &BookDocument.delete_category(&1, category_id), @category_signals)
  end

  def handle_call({:assign_category, expense_id, category_id, time}, _from, state) do
    run(state, time, &BookDocument.assign_category(&1, expense_id, category_id))
  end

  def handle_call({:unassign_category, expense_id, time}, _from, state) do
    run(state, time, &BookDocument.unassign_category(&1, expense_id))
  end

  def handle_call({:generate_sync_message, peer}, _from, state) do
    {sync_state, state} = ensure_sync_state(state, peer)
    {:reply, BookDocument.generate_sync_message(state.doc, sync_state), state}
  end

  def handle_call(:conflict_summary, _from, state) do
    {:reply, state.conflicts, state}
  end

  def handle_call(:dismiss_conflicts, _from, state) do
    # The summary is shared across a Book's windows, so broadcast: one window's dismiss
    # quiets every window's bell, not just the one that clicked.
    broadcast(state.id, {:book_updated, state.id})
    {:reply, :ok, %{state | conflicts: BookDocument.empty_conflict_summary()}}
  end

  def handle_call({:receive_sync_message, peer, message}, _from, state) do
    {sync_state, state} = ensure_sync_state(state, peer)
    new_doc = BookDocument.receive_sync_message(state.doc, sync_state, message)

    # A message that carried no new changes leaves the document byte-identical (an
    # Automerge save is deterministic for a given history), so there is nothing to
    # persist or announce — the closing acknowledgment rounds of an exchange take this
    # path. Only a message that actually advanced the document commits and broadcasts.
    if new_doc == state.doc do
      {:reply, :ok, state}
    else
      # Read what conflicted in the fold before adopting `new_doc`, diffing the prior
      # bytes against it (the sync transport returns only the merged bytes). Adopted
      # alongside the new bytes so both land, or neither does, on the same successful write.
      conflicts =
        BookDocument.accumulate_conflicts(
          state.conflicts,
          BookDocument.conflict_summary(state.doc, new_doc)
        )

      # A reconcile can fold in any kind of change, and the opaque bytes don't say
      # which — a concurrent category edit from the peer among them. A view that
      # refreshes its category cache only on `:categories_updated` (ADR 0018) would
      # miss that, so a committed reconcile conservatively emits the category signal
      # alongside `:book_updated` rather than trying to detect what moved.
      persist_and_commit(state, new_doc, :ok, @category_signals, conflicts)
    end
  rescue
    # A malformed message makes the decode NIF raise `ArgumentError`; return it rather
    # than crash the server, mirroring `run/4`.
    e in ArgumentError -> {:reply, {:error, e}, state}
  end

  # A viewer joined or left the Book's presence topic (see `register_viewer/1`).
  # Re-derive whether any viewer remains and arm or cancel the reap accordingly.
  @impl GenServer
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, state) do
    {:noreply, reconcile_viewers(state)}
  end

  # The grace period elapsed with no viewer. Re-check presence one last time — a
  # viewer can register in the window between the timer firing and this message being
  # handled — and only then persist-and-stop. `terminate/2` performs the final save;
  # every change was already persisted on write, so it is belt-and-suspenders (see
  # ADR 0007). Stopping `:normal` keeps the `:transient` child from being restarted.
  def handle_info(:reap, state) do
    if viewers_present?(state.id) do
      {:noreply, %{state | reap_timer: nil}}
    else
      {:stop, :normal, %{state | reap_timer: nil}}
    end
  end

  # Ignore stray messages rather than crash on them (ADR 0019).
  def handle_info(_message, state), do: {:noreply, state}

  # Reconciles the reap timer with the current presence set: a present viewer cancels
  # any pending reap, an empty set arms one. Arming is a no-op when a timer is already
  # pending.
  #
  # Reaching here at all means a viewer joined or left this Book's presence topic —
  # nothing else ever tracks on it — so "has this Book ever had a window?" needs no
  # separate flag. the rule that a Book which never had a window is never reaped holds
  # because a never-viewed Book is never sent a diff and so never reconciles.
  @spec reconcile_viewers(state()) :: state()
  defp reconcile_viewers(state) do
    if viewers_present?(state.id), do: cancel_reap(state), else: arm_reap(state)
  end

  defp arm_reap(%{reap_timer: nil} = state) do
    %{state | reap_timer: Process.send_after(self(), :reap, grace_ms())}
  end

  defp arm_reap(state), do: state

  defp cancel_reap(%{reap_timer: nil} = state), do: state

  defp cancel_reap(%{reap_timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | reap_timer: nil}
  end

  # True when at least one viewer is tracked on the Book's presence topic.
  @spec viewers_present?(Book.id()) :: boolean()
  defp viewers_present?(id), do: Presence.list(presence_topic(id)) != %{}

  # The viewer-disconnect grace period in milliseconds (default 60s), read at arm
  # time so config (and the test override) always wins over a compile-time capture.
  @spec grace_ms() :: non_neg_integer()
  defp grace_ms do
    :local_cents
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:viewer_grace_ms, 60_000)
  end

  # Decodes the current bytes into the functional core, runs one pure `command`, and
  # persists-then-commits the result. This is the whole "process shell": all domain
  # logic lives in `BookDocument`; the server only orchestrates decode → apply →
  # persist → broadcast (see ADR 0014). A NIF badarg raises `ArgumentError`; catch
  # it so a bad command returns an error rather than crashing the process.
  #
  # `extra_signals` are additional broadcast messages emitted alongside the standard
  # `:book_updated` on success — see `category_signals/0`.
  @spec run(state(), time :: integer(), command(), extra_signals :: [atom()]) ::
          {:reply, reply(), state()}
  defp run(state, time, command, extra_signals \\ []) do
    case command.(decode(state)) do
      {:ok, document, result} -> commit(state, document, time, {:ok, result}, extra_signals)
      {:ok, document} -> commit(state, document, time, :ok, extra_signals)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  rescue
    e in ArgumentError -> {:reply, {:error, e}, state}
  end

  defp decode(state), do: BookDocument.from_bytes(state.doc)

  # Persist first, commit to memory second: the new document is adopted (and
  # subscribers notified) only if it reached disk. A failed write — e.g. a full
  # disk — leaves the in-memory state untouched and returns the error to the
  # caller, rather than crashing and losing the change on restart.
  @spec commit(state(), BookDocument.t(), time :: integer(), reply(), extra_signals :: [atom()]) ::
          {:reply, reply(), state()}
  defp commit(state, document, time, reply, extra_signals) do
    new_doc = BookDocument.to_bytes(document, state.doc, time)
    persist_and_commit(state, new_doc, reply, extra_signals)
  end

  # The persist-then-commit tail shared by a domain command (`commit/5`, which encodes
  # the new document first) and a received sync message (which already holds the new
  # bytes from the codec). Persist first, adopt to memory and broadcast only on
  # success — a failed write leaves the in-memory state untouched and returns the error.
  #
  # `conflicts` is the summary a received sync message surfaced; a domain command passes
  # `nil` to leave the accumulated summary as it was. Either way it is adopted only on the
  # successful write, so the badge never gets ahead of the bytes on disk.
  @spec persist_and_commit(
          state(),
          new_doc :: binary(),
          reply(),
          extra_signals :: [atom()],
          conflicts :: BookDocument.conflict_summary() | nil
        ) :: {:reply, reply(), state()}
  defp persist_and_commit(state, new_doc, reply, extra_signals, conflicts \\ nil) do
    case BookStore.save(state.dir, state.id, new_doc) do
      :ok ->
        broadcast(state.id, {:book_updated, state.id})
        Enum.each(extra_signals, &broadcast(state.id, {&1, state.id}))
        {:reply, reply, %{state | doc: new_doc, conflicts: conflicts || state.conflicts}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Returns the per-peer sync state for `peer`, creating and storing a fresh one on
  # first contact. A `BookServer` keeps one sync state per remote peer (ADR 0025); the
  # handle mutates in place across calls, so it is stored once and reused.
  @spec ensure_sync_state(state(), peer()) :: {BookDocument.sync_state(), state()}
  defp ensure_sync_state(state, peer) do
    case Map.fetch(state.sync_states, peer) do
      {:ok, sync_state} ->
        {sync_state, state}

      :error ->
        sync_state = BookDocument.new_sync_state()
        {sync_state, %{state | sync_states: Map.put(state.sync_states, peer, sync_state)}}
    end
  end

  defp broadcast(id, message) do
    Phoenix.PubSub.broadcast(LocalCents.PubSub, topic(id), message)
  end

  @doc """
  The `Phoenix.PubSub` topic a subscriber listens on for a Book's changes.

  Follows the project topic-naming scheme (`docs/adr/0011-pubsub-topic-naming.md`):
  `"<kind>:<id>"`, owned by the broadcasting module so callers never hand-build
  the string.
  """
  @spec topic(Book.id()) :: String.t()
  def topic(id), do: "book:" <> id

  @doc """
  The `Phoenix.PubSub` topic a Book's viewers are tracked on in
  `LocalCents.Tracking.Presence`, kept distinct from `topic/1` so viewer-presence
  churn never mixes with the far more frequent `:book_updated` change broadcasts.
  """
  @spec presence_topic(Book.id()) :: String.t()
  def presence_topic(id), do: "book_presence:" <> id

  defp via(id), do: {:via, Registry, {@registry, id}}
end
