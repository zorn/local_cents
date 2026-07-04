defmodule LocalCents.Tracking.BookServer do
  @moduledoc """
  The per-Book runtime process: one GenServer owns the in-memory Automerge
  document for a single *open* Book and is the single source of truth for it (see
  [ADR 0007](0007-book-runtime-and-persistence.html)).

  Every command (add expense, rename) is applied to the in-memory document, then
  persisted through `LocalCents.Tracking.BookStore`, then **broadcast** on the
  Book's `Phoenix.PubSub` topic so that any subscribed LiveView re-renders. Book
  state deliberately never lives in a LiveView socket, which is what lets several
  viewers share one Book without divergence (needed for the future web version).

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

  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.ExAutomerge

  @registry LocalCents.Tracking.BookRegistry
  @supervisor LocalCents.Tracking.BookSupervisor

  # Client

  @doc """
  Ensures a BookServer for `id` is running, starting it under the supervisor if
  needed. Returns the pid either way.
  """
  @spec ensure_started(String.t()) :: {:ok, pid()} | {:error, term()}
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
  @spec alive?(String.t()) :: boolean()
  def alive?(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(id) when is_binary(id) do
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  @doc "Returns the Book's name."
  @spec name(String.t()) :: String.t()
  def name(id), do: GenServer.call(via(id), :name)

  @doc "Returns the Book's expenses."
  @spec list_expenses(String.t()) :: [map()]
  def list_expenses(id), do: GenServer.call(via(id), :list_expenses)

  @doc "Appends an expense, persists, and broadcasts."
  @spec add_expense(String.t(), String.t(), integer()) :: :ok
  def add_expense(id, description, amount) do
    GenServer.call(via(id), {:add_expense, description, amount})
  end

  @doc "Renames the Book, persists, and broadcasts."
  @spec rename(String.t(), String.t()) :: :ok
  def rename(id, new_name), do: GenServer.call(via(id), {:rename, new_name})

  @doc "Persists a final time and stops the process."
  @spec close(String.t()) :: :ok
  def close(id), do: GenServer.stop(via(id))

  # Server

  @impl GenServer
  def init(id) do
    # Label the process so it's identifiable by Book id in `:observer` and other
    # Erlang tooling — otherwise a `:via`-registered process shows only its pid.
    Process.set_label({:book_server, id})

    case BookStore.load(id) do
      {:ok, doc} -> {:ok, %{id: id, doc: doc}}
      {:error, reason} -> {:stop, {:load_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call(:name, _from, state) do
    {:reply, ExAutomerge.document_name(state.doc), state}
  end

  def handle_call(:list_expenses, _from, state) do
    {:reply, ExAutomerge.list_expenses(state.doc), state}
  end

  def handle_call({:add_expense, description, amount}, _from, state) do
    doc = ExAutomerge.add_expense(state.doc, description, amount)
    {:reply, :ok, persist_and_broadcast(%{state | doc: doc})}
  end

  def handle_call({:rename, new_name}, _from, state) do
    doc = ExAutomerge.rename(state.doc, new_name)
    {:reply, :ok, persist_and_broadcast(%{state | doc: doc})}
  end

  # A resident process still persists on every change; `terminate/2` is a
  # best-effort final save for the explicit-close path.
  @impl GenServer
  def terminate(_reason, state) do
    BookStore.save(state.id, state.doc)
    :ok
  end

  defp persist_and_broadcast(state) do
    :ok = BookStore.save(state.id, state.doc)
    Phoenix.PubSub.broadcast(LocalCents.PubSub, topic(state.id), {:book_updated, state.id})
    state
  end

  @doc "The `Phoenix.PubSub` topic a subscriber listens on for a Book's changes."
  @spec topic(String.t()) :: String.t()
  def topic(id), do: "book:" <> id

  defp via(id), do: {:via, Registry, {@registry, id}}
end
