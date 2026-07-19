defmodule LocalCents.Tracking do
  @moduledoc """
  The tracking context's public API — creating and opening `Book`s, managing the
  `Expense` entries inside them, and the `Category` list an Expense can be filed
  under.

  Call sites must go through this module; the internal implementation
  (`LocalCents.Tracking.BookServer`, `LocalCents.Tracking.BookStore`,
  `LocalCents.Tracking.ExAutomerge`) is private. The `Book`, `Expense`, and
  `Category` types make up the data contract, and
  `LocalCents.Tracking.Supervisor` is exported only so the application supervision
  tree can start the context's runtime.

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
  # layers can depend on the context directly. It exports the `Book`, `Expense`,
  # and `Category` types that make up its API contract, plus `Supervisor` so the
  # application supervision tree can start the context's runtime; the remaining
  # implementation modules (`BookServer`, `BookStore`, `ExAutomerge`) stay private.
  use Boundary, top_level?: true, deps: [], exports: [Book, Category, Expense, Supervisor]

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.BookServer
  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.Category
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
        _ = BookServer.broadcast_deleted(id)
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

  Returns an error if the Book cannot be read or the change cannot be persisted.

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
    with {:ok, bytes} <- BookStore.load(id) do
      # A rename only touches the Book's name, so we set it on the raw decoded state
      # directly rather than routing through `BookDocument.rename/2` (which would also
      # re-introduce a `BookDocument` dependency here). NOTE: this stays equivalent to
      # the open-Book path only while `BookDocument.rename/2` is a pure name-set — if
      # it ever grows logic (validation, derived fields), this closed-Book path must
      # be routed through the core too, or the two rename paths will diverge.
      state = %{ExAutomerge.decode(bytes) | name: new_name}
      BookStore.save(id, ExAutomerge.reconcile(bytes, state, seconds))
    end
  rescue
    # A readable-but-corrupt `.lcbook` makes the decode NIF raise; report it rather
    # than crash the caller, matching how `read_book/1` tolerates bad files.
    ArgumentError -> {:error, :invalid_document}
  end

  @doc """
  Adds an expense to an open Book from a map of `attrs` (`:date`, `:description`,
  `:cost`), returning the created `Expense`.

  Returns a changeset error if `attrs` fail validation (see
  `LocalCents.Tracking.Expense`), `:not_open` if the Book's process is not running
  (`open_book/1`), or another error if persisting the change fails. The new
  Expense's `id` is generated here (a side effect kept out of the
  functional core — see [ADR 0014](0014-functional-core-process-shell.html)).

  `now` stamps the change so the Book's `updated_at` advances (UTC). `today` seeds a
  blank date and must be the *user's* local date — on the desktop that is the
  machine's date (the default); a future web caller supplies the browser's date.
  Both are injectable for tests.
  """
  @spec add_expense(Book.id(), attrs :: map(), now :: DateTime.t(), today :: Date.t()) ::
          {:ok, Expense.t()} | {:error, term()}
  def add_expense(id, attrs, now \\ DateTime.utc_now(), today \\ local_today())
      when is_binary(id) and is_map(attrs) do
    BookServer.add_expense(id, attrs, Ecto.UUID.generate(), today, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Edits the Expense `expense_id` in an open Book, replacing its editable fields with
  `attrs` (a full replace). Returns the updated `Expense`.

  Returns a changeset error on invalid `attrs`, `:not_found` for an unknown
  `expense_id`, `:not_open` if the Book's process is not running, or another error
  if persisting fails. `now`/`today` behave as in `add_expense/4`.
  """
  @spec edit_expense(
          Book.id(),
          Expense.id(),
          attrs :: map(),
          now :: DateTime.t(),
          today :: Date.t()
        ) ::
          {:ok, Expense.t()} | {:error, term()}
  def edit_expense(id, expense_id, attrs, now \\ DateTime.utc_now(), today \\ local_today())
      when is_binary(id) and is_binary(expense_id) and is_map(attrs) do
    BookServer.edit_expense(id, expense_id, attrs, today, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Hard-deletes the Expense `expense_id` from an open Book.

  Returns `:not_found` for an unknown `expense_id`, `:not_open` if the Book's
  process is not running, or another error if persisting fails. `now` stamps the
  change so `updated_at` advances.
  """
  @spec delete_expense(Book.id(), Expense.id(), now :: DateTime.t()) :: :ok | {:error, term()}
  def delete_expense(id, expense_id, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(expense_id) do
    BookServer.delete_expense(id, expense_id, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Lists the expenses of an open Book.

  The list order is not a contract callers should rely on (it is not stable across
  a CRDT merge); sort in the view for display. Returns `:not_open` if the Book's
  process is not running (`open_book/1`), matching the mutating functions rather
  than crashing the caller.
  """
  @spec list_expenses(Book.id()) :: [Expense.t()] | {:error, :not_open}
  def list_expenses(id) when is_binary(id) do
    BookServer.list_expenses(id)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Lists the categories of an open Book.

  The list order is not a contract callers should rely on (it is not stable across a
  CRDT merge); sort in the view for display. Returns `:not_open` if the Book's
  process is not running (`open_book/1`).
  """
  @spec list_categories(Book.id()) :: [Category.t()] | {:error, :not_open}
  def list_categories(id) when is_binary(id) do
    BookServer.list_categories(id)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Adds a category to an open Book from a map of `attrs` (`:name`), returning the
  created `Category`.

  Returns a changeset error if `attrs` fail validation (a blank `name` — see
  `LocalCents.Tracking.Category`), `:not_open` if the Book's process is not running,
  or another error if persisting fails. The new Category's `id` is generated here (a
  side effect kept out of the functional core — see
  [ADR 0014](0014-functional-core-process-shell.html)). `now` stamps the change so
  `updated_at` advances (UTC).
  """
  @spec add_category(Book.id(), attrs :: map(), now :: DateTime.t()) ::
          {:ok, Category.t()} | {:error, term()}
  def add_category(id, attrs, now \\ DateTime.utc_now())
      when is_binary(id) and is_map(attrs) do
    BookServer.add_category(id, attrs, Ecto.UUID.generate(), unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Renames the Category `category_id` in an open Book from `attrs` (`:name`),
  returning the updated `Category`.

  A rename touches only the Category — filed Expenses reference it by stable id and
  are left untouched. Returns a changeset error on invalid `attrs`, `:not_found` for
  an unknown `category_id`, `:not_open` if the Book's process is not running, or
  another error if persisting fails.
  """
  @spec rename_category(Book.id(), Category.id(), attrs :: map(), now :: DateTime.t()) ::
          {:ok, Category.t()} | {:error, term()}
  def rename_category(id, category_id, attrs, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(category_id) and is_map(attrs) do
    BookServer.rename_category(id, category_id, attrs, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Deletes the Category `category_id` from an open Book, un-filing every Expense
  filed under it so they become Uncategorized (see
  [ADR 0005](0005-categories-not-tags.html)).

  Returns `:not_found` for an unknown `category_id`, `:not_open` if the Book's
  process is not running, or another error if persisting fails. `now` stamps the
  change so `updated_at` advances.
  """
  @spec delete_category(Book.id(), Category.id(), now :: DateTime.t()) :: :ok | {:error, term()}
  def delete_category(id, category_id, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(category_id) do
    BookServer.delete_category(id, category_id, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Files the Expense `expense_id` under the Category `category_id` in an open Book
  (replacing any prior Category — an Expense has at most one), returning the updated
  `Expense`.

  Returns `:expense_not_found` or `:category_not_found` when either is unknown,
  `:not_open` if the Book's process is not running, or another error if persisting
  fails. `now` stamps the change so `updated_at` advances.
  """
  @spec assign_category(Book.id(), Expense.id(), Category.id(), now :: DateTime.t()) ::
          {:ok, Expense.t()} | {:error, term()}
  def assign_category(id, expense_id, category_id, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(expense_id) and is_binary(category_id) do
    BookServer.assign_category(id, expense_id, category_id, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Un-files the Expense `expense_id` in an open Book (nulls its `category_id` so it
  becomes Uncategorized), returning the updated `Expense`.

  Returns `:expense_not_found` for an unknown `expense_id`, `:not_open` if the
  Book's process is not running, or another error if persisting fails. `now` stamps
  the change so `updated_at` advances.
  """
  @spec unassign_category(Book.id(), Expense.id(), now :: DateTime.t()) ::
          {:ok, Expense.t()} | {:error, term()}
  def unassign_category(id, expense_id, now \\ DateTime.utc_now())
      when is_binary(id) and is_binary(expense_id) do
    BookServer.unassign_category(id, expense_id, unix_seconds(now))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Subscribes the calling process to a Book's change broadcasts.

  After subscribing, the caller receives `{:book_updated, id}` messages whenever
  the Book changes and should re-read via `list_expenses/1`.
  """
  @spec subscribe(Book.id()) :: :ok | {:error, term()}
  def subscribe(id) when is_binary(id), do: BookServer.subscribe(id)

  # The user's local calendar date, used as the default when an expense is saved
  # without a date. On the desktop the server and user share a machine, so the
  # machine's local date is the user's; a future web caller must pass the browser's
  # date explicitly rather than rely on this (the server's zone is not the user's).
  defp local_today, do: NaiveDateTime.to_date(NaiveDateTime.local_now())

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
