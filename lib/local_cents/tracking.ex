defmodule LocalCents.Tracking do
  @moduledoc """
  Public API for the tracking context: creating and opening `Book`s and managing
  the `Expense` entries inside them.

  Call sites must go through this module; the internal implementation
  (`BookServer`, `BookStore`, `ExAutomerge`) is private. Only the `Book` and
  `Expense` types make up the context's contract.

  ## How Books live at runtime

  A Book is persisted as one Automerge document in a `.lcbook` file (see
  [ADR 0009](0009-book-file-format.html)); the library is the enumeration of the
  books directory. While a Book is open, a per-Book `BookServer` process is the
  single source of truth for it (see
  [ADR 0007](0007-book-runtime-and-persistence.html)). Mutating functions here
  route to that process, which applies the change, persists it, and broadcasts to
  subscribers; read functions are served from the process's in-memory document.

  Identify a Book by its `id` (a UUID string, also its file name). `create_book/1`
  and `list_books/0` return `Book` structs pairing that id with the name.
  """

  # The tracking context boundary. It is a top-level boundary (a peer of the
  # core and web layers rather than nested inside `LocalCents`) so that other
  # layers can depend on the context directly. It exports only the `Book` and
  # `Expense` types that make up its API contract; the implementation modules
  # (`BookServer`, `BookStore`, `ExAutomerge`) stay private.
  use Boundary, top_level?: true, deps: [], exports: [Book, Expense, Supervisor]

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.BookServer
  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.ExAutomerge
  alias LocalCents.Tracking.Expense

  require Logger

  @doc """
  Creates a new, empty Book named `name`, persists it, and starts its runtime
  process. Returns the `Book`.
  """
  @spec create_book(Book.name()) :: {:ok, Book.t()} | {:error, term()}
  def create_book(name) when is_binary(name) do
    id = BookStore.generate_id()

    with :ok <- BookStore.save(id, ExAutomerge.new_document(name)),
         {:ok, _pid} <- BookServer.ensure_started(id) do
      {:ok, %Book{id: id, name: name}}
    else
      {:error, reason} ->
        # If the process failed to start after the file was written, remove it so a
        # phantom Book doesn't linger in `list_books/0`. (A no-op if save failed.)
        BookStore.delete(id)
        {:error, reason}
    end
  end

  @doc """
  Ensures the Book's runtime process is running (idempotent). Returns `:ok` or an
  error if no Book with `id` exists on disk.
  """
  @spec open_book(Book.id()) :: :ok | {:error, term()}
  def open_book(id) when is_binary(id) do
    case BookServer.ensure_started(id) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Persists and stops the Book's runtime process. The `.lcbook` file remains.
  """
  @spec close_book(Book.id()) :: :ok
  def close_book(id) when is_binary(id) do
    if BookServer.alive?(id), do: BookServer.close(id)
    :ok
  catch
    # The server can die between alive?/1 and close/1; GenServer.stop then exits
    # :noproc. Closing an already-gone Book is still success.
    :exit, _ -> :ok
  end

  @doc """
  Returns every Book found in the books directory, as `Book` structs.

  Reads each file's name directly (matching ADR 0007's "reads a bit of metadata
  from each file on load") without starting a process per Book.
  """
  @spec list_books() :: [Book.t()]
  def list_books do
    BookStore.list_ids()
    |> Enum.map(&read_book/1)
    |> Enum.reject(&is_nil/1)
  end

  # Reads one Book's identity, tolerating a file that cannot be read or is not a
  # valid Book document, so a single bad `.lcbook` never blanks the whole library.
  defp read_book(id) do
    case BookStore.load(id) do
      {:ok, doc} ->
        %Book{id: id, name: ExAutomerge.document_name(doc)}

      {:error, reason} ->
        Logger.warning("Skipping unreadable book file #{inspect(id)}: #{inspect(reason)}")
        nil
    end
  rescue
    ArgumentError ->
      Logger.warning("Skipping unreadable book file #{inspect(id)} (not a valid Book document)")
      nil
  end

  @doc """
  Permanently deletes the Book: stops its process (if running) and removes the
  `.lcbook` file.
  """
  @spec delete_book(Book.id()) :: :ok | {:error, term()}
  def delete_book(id) when is_binary(id) do
    :ok = close_book(id)
    BookStore.delete(id)
  end

  @doc """
  Renames an open Book.

  Returns `{:error, :not_open}` if the Book's process is not running
  (`open_book/1`), or `{:error, reason}` if persisting the change fails.
  """
  @spec rename_book(Book.id(), Book.name()) :: :ok | {:error, term()}
  def rename_book(id, new_name) when is_binary(id) and is_binary(new_name) do
    BookServer.rename(id, new_name)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Adds an expense to an open Book.

  Returns `{:error, :not_open}` if the Book's process is not running
  (`open_book/1`), or `{:error, reason}` if persisting the change fails.
  """
  @spec add_expense(Book.id(), Expense.t()) :: :ok | {:error, term()}
  def add_expense(id, %Expense{description: description, amount: amount}) when is_binary(id) do
    BookServer.add_expense(id, description, amount)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Lists the expenses of an open Book.

  Returns `{:error, :not_open}` if the Book's process is not running
  (`open_book/1`), matching `add_expense/2` and `rename_book/2` rather than
  crashing the caller.
  """
  @spec list_expenses(Book.id()) :: [Expense.t()] | {:error, :not_open}
  def list_expenses(id) when is_binary(id) do
    id
    |> BookServer.list_expenses()
    |> Enum.map(fn %{description: description, amount: amount} ->
      %Expense{description: description, amount: amount}
    end)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Subscribes the calling process to a Book's change broadcasts.

  After subscribing, the caller receives `{:book_updated, id}` messages whenever
  the Book changes and should re-read via `list_expenses/1`.
  """
  @spec subscribe(Book.id()) :: :ok | {:error, term()}
  def subscribe(id) when is_binary(id) do
    Phoenix.PubSub.subscribe(LocalCents.PubSub, BookServer.topic(id))
  end
end
