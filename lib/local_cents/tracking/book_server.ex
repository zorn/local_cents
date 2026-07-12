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

  ## Lifecycle (interim)

  For the MVP a BookServer starts when a Book is opened and **stays resident until
  it is explicitly closed** (`close/1`) or the application shuts down. ADR 0007
  ultimately calls for the process to persist once more and stop when the *last
  viewer disconnects* (auto-shutdown-on-last-viewer). That requires monitoring
  LiveView subscribers, which we defer until the windows/LiveViews that create
  those subscribers exist — tracked in
  [issue #74](https://github.com/zorn/local_cents/issues/74).
  """

  # `:transient` restart: a crash is recovered by the supervisor (the process
  # restarts and reloads the last persisted document), but an intentional
  # `close/1` — which stops with reason `:normal` — stays stopped. The default
  # `:permanent` would resurrect a just-closed Book, defeating `close/1`.
  use GenServer, restart: :transient

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.Expense

  @registry LocalCents.Tracking.BookRegistry
  @supervisor LocalCents.Tracking.BookSupervisor

  # Client

  @doc """
  Ensures a BookServer for `id` is running, starting it under the supervisor if
  needed. Returns the pid either way.
  """
  @spec ensure_started(Book.id()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, id}) do
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

  @spec start_link(Book.id()) :: GenServer.on_start()
  def start_link(id) when is_binary(id) do
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  @doc "Returns the Book's name."
  @spec name(Book.id()) :: Book.name()
  def name(id), do: GenServer.call(via(id), :name)

  @doc """
  Returns the Book's expenses. The list order is not a contract callers should
  rely on (it is not stable across a CRDT merge); the view sorts for display.
  """
  @spec list_expenses(Book.id()) :: [Expense.t()]
  def list_expenses(id), do: GenServer.call(via(id), :list_expenses)

  @doc """
  Adds an expense built from `attrs`, persists, and broadcasts. `id` is the UUID
  assigned to the new Expense and `today` seeds a blank date (both injected by the
  caller). Returns `{:ok, Expense.t()}`, `{:error, changeset}` on invalid `attrs`,
  or `{:error, reason}` if the write fails.

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
  and broadcasts. Returns `{:ok, Expense.t()}`, `{:error, changeset}` on invalid
  `attrs`, `{:error, :not_found}` for an unknown `expense_id`, or `{:error, reason}`
  if the write fails.
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
  Hard-deletes the Expense `expense_id`, persists, and broadcasts. Returns `:ok`,
  `{:error, :not_found}` for an unknown `expense_id`, or `{:error, reason}` if the
  write fails.
  """
  @spec delete_expense(Book.id(), Expense.id(), time :: integer()) :: :ok | {:error, term()}
  def delete_expense(id, expense_id, time) when is_binary(id) do
    GenServer.call(via(id), {:delete_expense, expense_id, time})
  end

  @doc """
  Renames the Book, persists, and broadcasts. Returns `{:error, reason}` if the
  write fails.

  `time` is the unix-seconds stamp recorded on the change so the Book's
  `updated_at` advances (see [ADR 0012](0012-book-last-updated-timestamp.html)).
  """
  @spec rename(Book.id(), Book.name(), time :: integer()) :: :ok | {:error, term()}
  def rename(id, new_name, time) when is_binary(id) do
    GenServer.call(via(id), {:rename, new_name, time})
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
  Broadcasts that the Book was deleted, so subscribers (e.g. an open document
  window) can react. Called after the file is removed, when no process remains to
  broadcast from within.
  """
  @spec broadcast_deleted(Book.id()) :: :ok | {:error, term()}
  def broadcast_deleted(id) when is_binary(id) do
    Phoenix.PubSub.broadcast(LocalCents.PubSub, topic(id), {:book_updated, id})
  end

  # Server

  @impl GenServer
  def init(id) do
    # Label the process so it's identifiable by Book id in `:observer` and other
    # Erlang tooling — otherwise a `:via`-registered process shows only its pid.
    Process.set_label({:book_server, id})

    with {:ok, doc} <- BookStore.load(id),
         :ok <- validate_document(doc) do
      {:ok, %{id: id, doc: doc}}
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

  # Decodes the current bytes into the functional core, runs one pure `command`, and
  # persists-then-commits the result. This is the whole "process shell": all domain
  # logic lives in `BookDocument`; the server only orchestrates decode → apply →
  # persist → broadcast (see ADR 0014). A NIF badarg raises `ArgumentError`; catch
  # it so a bad command returns an error rather than crashing the process.
  defp run(state, time, command) do
    case command.(decode(state)) do
      {:ok, document, result} -> commit(state, document, time, {:ok, result})
      {:ok, document} -> commit(state, document, time, :ok)
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
  defp commit(state, document, time, reply) do
    new_doc = BookDocument.to_bytes(document, state.doc, time)

    case BookStore.save(state.id, new_doc) do
      :ok ->
        Phoenix.PubSub.broadcast(LocalCents.PubSub, topic(state.id), {:book_updated, state.id})
        {:reply, reply, %{state | doc: new_doc}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @doc """
  The `Phoenix.PubSub` topic a subscriber listens on for a Book's changes.

  Follows the project topic-naming scheme (`docs/adr/0011-pubsub-topic-naming.md`):
  `"<kind>:<id>"`, owned by the broadcasting module so callers never hand-build
  the string.
  """
  @spec topic(Book.id()) :: String.t()
  def topic(id), do: "book:" <> id

  defp via(id), do: {:via, Registry, {@registry, id}}
end
