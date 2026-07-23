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
  @spec report(Book.id(), Report.range(), DateTime.t()) :: Report.t()
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

  # The GenServer state: the Book's id, its current encoded document bytes, and the
  # books directory it persists to (injected at start so the persistence path is not
  # coupled to a global — see `ensure_started/2`). Every command decodes `doc` into a
  # `BookDocument`, runs, and re-encodes.
  @typep state() :: %{id: Book.id(), doc: binary(), dir: String.t()}

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
      {:ok, %{id: id, doc: doc, dir: dir}}
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

    case BookStore.save(state.dir, state.id, new_doc) do
      :ok ->
        broadcast(state.id, {:book_updated, state.id})
        Enum.each(extra_signals, &broadcast(state.id, {&1, state.id}))
        {:reply, reply, %{state | doc: new_doc}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
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

  defp via(id), do: {:via, Registry, {@registry, id}}
end
