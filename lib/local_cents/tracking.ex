defmodule LocalCents.Tracking do
  @moduledoc """
  The tracking context's public API — creating and opening `Book`s and managing
  the `Expense` entries inside them.

  Call sites must go through this module; the internal implementation
  (`LocalCents.Tracking.BookServer`, `LocalCents.Tracking.BookStore`,
  `LocalCents.Tracking.ExAutomerge`) is private. The `Book` and `Expense` types
  make up the data contract, and `LocalCents.Tracking.Supervisor` is exported
  only so the application supervision tree can start the context's runtime.

  ## How Books live at runtime

  A Book is persisted as one Automerge document in a `.lcbook` file (see
  [ADR 0009](0009-book-file-format.html)); the library is the enumeration of the
  books directory. While a Book is open, a per-Book
  [`BookServer`](`LocalCents.Tracking.BookServer`) process is the single source
  of truth for it (see
  [ADR 0007](0007-book-runtime-and-persistence.html)). Mutating functions here
  route to that process, which applies the change, persists it, and broadcasts to
  subscribers; read functions are served from the process's in-memory document.

  Identify a Book by its `id` (a UUID string, also its file name). `create_book/2`
  and `list_books/0` return `Book` structs pairing that id with the name and a
  `updated_at` derived from the document's change history (see
  [ADR 0012](0012-book-last-updated-timestamp.html)).
  """

  # The tracking context boundary. It is a top-level boundary (a peer of the
  # core and web layers rather than nested inside `LocalCents`) so that other
  # layers can depend on the context directly. It exports the `Book` and `Expense`
  # types that make up its API contract, plus `Supervisor` so the application
  # supervision tree can start the context's runtime; the remaining implementation
  # modules (`BookServer`, `BookStore`, `ExAutomerge`) stay private.
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

  `now` stamps the document's first change and seeds the Book's `updated_at`; it
  defaults to the current time and is injectable for tests.
  """
  @spec create_book(Book.name(), now :: DateTime.t()) :: {:ok, Book.t()} | {:error, term()}
  def create_book(name, now \\ DateTime.utc_now()) when is_binary(name) do
    id = BookStore.generate_id()
    seconds = unix_seconds(now)

    with :ok <- BookStore.save(id, ExAutomerge.new_document(name, seconds)),
         {:ok, _pid} <- BookServer.ensure_started(id) do
      {:ok, %Book{id: id, name: name, updated_at: to_datetime(seconds)}}
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

  @doc """
  Returns the `Book` with `id`, or `nil` if no such Book exists in the library.
  """
  @spec get_book(Book.id()) :: Book.t() | nil
  def get_book(id) when is_binary(id) do
    # Read only this Book's file rather than enumerating the whole library. The
    # `list_ids/0` guard keeps an absent id quiet (no `read_book/1` warning) and
    # cheap (a directory listing, not a parse of every `.lcbook`).
    if id in BookStore.list_ids(), do: read_book(id)
  end

  # Reads one Book's library view, tolerating a file that cannot be read or is not
  # a valid Book document, so a single bad `.lcbook` never blanks the whole library.
  defp read_book(id) do
    case BookStore.load(id) do
      {:ok, doc} ->
        %Book{
          id: id,
          name: ExAutomerge.document_name(doc),
          updated_at: to_datetime(ExAutomerge.document_updated_at(doc))
        }

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

    case BookStore.delete(id) do
      :ok ->
        # Announce the change on the Book's topic after the file is gone, so a
        # subscriber that re-reads finds it absent. Best-effort: the delete has
        # already succeeded, so the broadcast result is not our concern.
        _ = Phoenix.PubSub.broadcast(LocalCents.PubSub, BookServer.topic(id), {:book_updated, id})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Renames a Book, whether or not it is currently open.

  When the Book has a running [`BookServer`](`LocalCents.Tracking.BookServer`) —
  i.e. its document window is open — the rename goes through that process, which
  persists it and broadcasts so the open window updates its title live. When the
  Book is closed, its `.lcbook` file is the source of truth (see
  [ADR 0007](0007-book-runtime-and-persistence.html)), so the rename is applied to
  the file directly without starting a runtime process.

  Returns `{:error, reason}` if the Book cannot be read or the change cannot be
  persisted.

  `now` stamps the rename change so the Book's `updated_at` advances; it defaults
  to the current time and is injectable for tests.
  """
  @spec rename_book(Book.id(), Book.name(), now :: DateTime.t()) :: :ok | {:error, term()}
  def rename_book(id, new_name, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(new_name) do
    case BookServer.alive?(id) do
      true -> BookServer.rename(id, new_name, unix_seconds(now))
      false -> rename_on_disk(id, new_name, unix_seconds(now))
    end
  catch
    # The server can die between alive?/1 and the rename call; the document is
    # persisted after every change, so falling back to the on-disk rename is safe.
    :exit, {:noproc, _} -> rename_on_disk(id, new_name, unix_seconds(now))
  end

  # Renames a closed Book by rewriting its file. No `BookServer` owns the document,
  # so disk is the source of truth and no process needs to start just to rename.
  defp rename_on_disk(id, new_name, seconds) do
    with {:ok, doc} <- BookStore.load(id) do
      BookStore.save(id, ExAutomerge.rename(doc, new_name, seconds))
    end
  rescue
    # A readable-but-corrupt `.lcbook` makes the rename NIF raise; report it rather
    # than crash the caller, matching how `read_book/1` tolerates bad files.
    ArgumentError -> {:error, :invalid_document}
  end

  @doc """
  Adds an expense to an open Book.

  Returns `{:error, :not_open}` if the Book's process is not running
  (`open_book/1`), or `{:error, reason}` if persisting the change fails.

  `now` stamps the change so the Book's `updated_at` advances; it defaults to the
  current time and is injectable for tests.
  """
  @spec add_expense(Book.id(), Expense.t(), now :: DateTime.t()) :: :ok | {:error, term()}
  def add_expense(
        id,
        %Expense{description: description, amount: amount},
        now \\ DateTime.utc_now()
      )
      when is_binary(id) do
    BookServer.add_expense(id, description, amount, unix_seconds(now))
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

  # The change stamp we hand the NIFs is whole unix seconds — the resolution
  # Automerge records — so a Book's `updated_at` round-trips at the same precision
  # whether it was just created or later re-read from the document.
  defp unix_seconds(%DateTime{} = now), do: DateTime.to_unix(now, :second)

  # A Book has no `updated_at` (and the library renders no "last updated" line) when
  # there's no usable stamp. We mirror the NIF's `time > 0` rule here so a freshly
  # created Book agrees with a later `list_books/0` read: `document_updated_at/1`
  # returns `nil` for an unset (`0`) stamp, so a `0` seed must become `nil` too rather
  # than the Unix epoch.
  defp to_datetime(seconds) when is_integer(seconds) and seconds > 0,
    do: DateTime.from_unix!(seconds, :second)

  defp to_datetime(_seconds), do: nil
end
