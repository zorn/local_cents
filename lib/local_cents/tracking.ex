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
  and `list_books/1` return `Book` structs pairing that id with the name and a
  `updated_at` derived from the document's change history (see
  [ADR 0012](0012-book-last-updated-timestamp.html)).

  ## Injected options

  Functions that need a clock, a "today" date, or a books directory take them as a
  trailing keyword list validated by `NimbleOptions`, so a mistyped key raises
  rather than being silently ignored:

    * `:books_dir` — the directory holding the `.lcbook` files; defaults to
      `LocalCents.Tracking.BookStore.default_dir/0`.
    * `:now` — a `DateTime` stamping the change (and seeding `updated_at`); defaults
      to `DateTime.utc_now/0`.
    * `:today` — a `Date` seeding a blank Expense date; defaults to the machine's
      local date.

  Injecting these keeps the functional core clock-free (see
  [ADR 0014](0014-functional-core-process-shell.html)) and lets the suite run with
  per-test directories concurrently (see
  `docs/research/avoiding-async-false-tests.md`). Their defaults are dynamic, so
  they are applied after validation rather than declared in the schema.
  """

  # As the context's public facade, this module coordinates every internal piece by
  # design — the runtime (`BookServer`), persistence (`BookStore`), the CRDT codec
  # (`ExAutomerge`), and each domain type (`Book`, `Expense`, `Category`) — on top of
  # stdlib and `NimbleOptions`. That breadth is the point of a facade, not a smell to
  # refactor away, so it opts out of the project-wide dependency cap rather than
  # fragmenting the single entry point. Same rationale as
  # `LocalCents.Tracking.BookServer`, which mirrors this API.
  # credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies

  # The tracking context boundary. It is a top-level boundary (a peer of the
  # core and web layers rather than nested inside `LocalCents`) so that other
  # layers can depend on the context directly. It exports the `Book`, `Expense`,
  # and `Category` types that make up its API contract, plus `Supervisor` so the
  # application supervision tree can start the context's runtime; the remaining
  # implementation modules (`BookServer`, `BookStore`, `ExAutomerge`) stay private.
  use Boundary,
    top_level?: true,
    deps: [],
    exports: [Book, Category, Expense, Month, Report, Supervisor]

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.BookServer
  alias LocalCents.Tracking.BookStore
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.ExAutomerge
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.QuickAdd
  alias LocalCents.Tracking.Report

  require Logger

  # One spec per injectable option, composed into a per-function schema below. The
  # defaults live in `opt_dir/1`, `opt_now/1`, and `opt_today/1`, not here — a
  # `NimbleOptions` default is captured at compile time, which would freeze
  # `DateTime.utc_now/0` and the platform path.
  @books_dir_opt [type: :string]
  @now_opt [type: {:struct, DateTime}]
  @today_opt [type: {:struct, Date}]

  @books_dir_now_schema NimbleOptions.new!(books_dir: @books_dir_opt, now: @now_opt)
  @books_dir_schema NimbleOptions.new!(books_dir: @books_dir_opt)
  @now_today_schema NimbleOptions.new!(now: @now_opt, today: @today_opt)
  @now_schema NimbleOptions.new!(now: @now_opt)

  @doc """
  Creates a new, empty Book named `name`, persists it, and starts its runtime
  process. Returns the `Book`.

  Options: `:books_dir` and `:now` (see the moduledoc). `:now` seeds the Book's
  `updated_at`.
  """
  @spec create_book(Book.name(), opts :: keyword()) :: {:ok, Book.t()} | {:error, term()}
  def create_book(name, opts \\ []) when is_binary(name) do
    opts = NimbleOptions.validate!(opts, @books_dir_now_schema)
    dir = opt_dir(opts)
    id = BookStore.generate_id()
    seconds = unix_seconds(opt_now(opts))

    with :ok <- BookStore.save(dir, id, ExAutomerge.new_document(name, seconds)),
         {:ok, _pid} <- BookServer.ensure_started(id, dir) do
      {:ok, %Book{id: id, name: name, updated_at: to_datetime(seconds)}}
    else
      {:error, reason} ->
        # If the process failed to start after the file was written, remove it so a
        # phantom Book doesn't linger in `list_books/1`. (A no-op if save failed.)
        BookStore.delete(dir, id)
        {:error, reason}
    end
  end

  @doc """
  Ensures the Book's runtime process is running (idempotent). Returns `:ok` or an
  error if no Book with `id` exists on disk.

  Options: `:books_dir` (see the moduledoc). It applies only when the process is
  first started; an already-open Book keeps its directory.
  """
  @spec open_book(Book.id(), opts :: keyword()) :: :ok | {:error, term()}
  def open_book(id, opts \\ []) when is_binary(id) do
    opts = NimbleOptions.validate!(opts, @books_dir_schema)
    dir = opt_dir(opts)

    case BookServer.ensure_started(id, dir) do
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

  Options: `:books_dir` (see the moduledoc).
  """
  @spec list_books(opts :: keyword()) :: [Book.t()]
  def list_books(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @books_dir_schema)
    dir = opt_dir(opts)

    dir
    |> BookStore.list_ids()
    |> Enum.map(&read_book(dir, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns the `Book` with `id`, or `nil` if no such Book exists in the library.

  Options: `:books_dir` (see the moduledoc).
  """
  @spec get_book(Book.id(), opts :: keyword()) :: Book.t() | nil
  def get_book(id, opts \\ []) when is_binary(id) do
    opts = NimbleOptions.validate!(opts, @books_dir_schema)
    dir = opt_dir(opts)

    # Read only this Book's file rather than enumerating the whole library. The
    # `list_ids/1` guard keeps an absent id quiet (no `read_book/2` warning) and
    # cheap (a directory listing, not a parse of every `.lcbook`).
    if id in BookStore.list_ids(dir), do: read_book(dir, id)
  end

  # Reads one Book's library view, tolerating a file that cannot be read or is not
  # a valid Book document, so a single bad `.lcbook` never blanks the whole library.
  defp read_book(dir, id) do
    case BookStore.load(dir, id) do
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

  Options: `:books_dir` (see the moduledoc).
  """
  @spec delete_book(Book.id(), opts :: keyword()) :: :ok | {:error, term()}
  def delete_book(id, opts \\ []) when is_binary(id) do
    opts = NimbleOptions.validate!(opts, @books_dir_schema)
    dir = opt_dir(opts)
    :ok = close_book(id)

    case BookStore.delete(dir, id) do
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

  Options: `:books_dir` (the closed-Book path's directory) and `:now` (see the
  moduledoc). `:now` advances the Book's `updated_at`.
  """
  @spec rename_book(Book.id(), Book.name(), opts :: keyword()) :: :ok | {:error, term()}
  def rename_book(id, new_name, opts \\ []) when is_binary(id) and is_binary(new_name) do
    opts = NimbleOptions.validate!(opts, @books_dir_now_schema)
    dir = opt_dir(opts)
    seconds = unix_seconds(opt_now(opts))

    try do
      if BookServer.alive?(id) do
        BookServer.rename(id, new_name, seconds)
      else
        rename_on_disk(dir, id, new_name, seconds)
      end
    catch
      # The server can die between alive?/1 and the rename call; the document is
      # persisted after every change, so falling back to the on-disk rename is safe.
      :exit, {:noproc, _} -> rename_on_disk(dir, id, new_name, seconds)
    end
  end

  # Renames a closed Book by rewriting its file. No `BookServer` owns the document,
  # so disk is the source of truth and no process needs to start just to rename.
  defp rename_on_disk(dir, id, new_name, seconds) do
    with {:ok, bytes} <- BookStore.load(dir, id) do
      # A rename only touches the Book's name, so we set it on the raw decoded state
      # directly rather than routing through `BookDocument.rename/2` (which would also
      # re-introduce a `BookDocument` dependency here). NOTE: this stays equivalent to
      # the open-Book path only while `BookDocument.rename/2` is a pure name-set — if
      # it ever grows logic (validation, derived fields), this closed-Book path must
      # be routed through the core too, or the two rename paths will diverge.
      state = %{ExAutomerge.decode(bytes) | name: new_name}
      BookStore.save(dir, id, ExAutomerge.reconcile(bytes, state, seconds))
    end
  rescue
    # A readable-but-corrupt `.lcbook` makes the decode NIF raise; report it rather
    # than crash the caller, matching how `read_book/2` tolerates bad files.
    ArgumentError -> {:error, :invalid_document}
  end

  @doc """
  Adds an expense to an open Book from a map of `attrs` (`:date`, `:description`,
  `:cost`), returning the created `Expense`.

  Returns a changeset error if `attrs` fail validation (see
  `LocalCents.Tracking.Expense`), a `:not_open` error if the Book's process is not
  running (`open_book/2`), or another error if persisting the change fails. The new
  Expense's `id` is generated here (a side effect kept out of the functional core —
  see [ADR 0014](0014-functional-core-process-shell.html)).

  Options: `:now` and `:today` (see the moduledoc). `:today` seeds a blank date and
  must be the *user's* local date — on the desktop that is the machine's date (the
  default); a future web caller supplies the browser's date.
  """
  @spec add_expense(Book.id(), attrs :: map(), opts :: keyword()) ::
          {:ok, Expense.t()} | {:error, term()}
  def add_expense(id, attrs, opts \\ []) when is_binary(id) and is_map(attrs) do
    opts = NimbleOptions.validate!(opts, @now_today_schema)

    BookServer.add_expense(
      id,
      attrs,
      Ecto.UUID.generate(),
      opt_today(opts),
      unix_seconds(opt_now(opts))
    )
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Adds an expense to an open Book from a single quick-add `line`, returning the created
  `Expense`.

  The line is parsed by `LocalCents.Tracking.QuickAdd` — a trailing amount becomes the
  Cost and the rest the Description — and the result is created through `add_expense/3`,
  so validation, id generation, and the `:now`/`:today` injection are all shared with
  the full editor. A blank or whitespace-only line creates nothing and yields a
  `:blank` error; every other error mirrors `add_expense/3`.

  Options: `:now` and `:today` (see the moduledoc), as in `add_expense/3`.
  """
  @spec quick_add_expense(Book.id(), line :: String.t(), opts :: keyword()) ::
          {:ok, Expense.t()} | {:error, term()}
  def quick_add_expense(id, line, opts \\ []) when is_binary(id) and is_binary(line) do
    case QuickAdd.parse(line) do
      {:ok, attrs} -> add_expense(id, attrs, opts)
      :blank -> {:error, :blank}
    end
  end

  @doc """
  Edits the Expense `expense_id` in an open Book, replacing its editable fields with
  `attrs` (a full replace). Returns the updated `Expense`.

  Returns a changeset error on invalid `attrs`, a `:not_found` error for an unknown
  `expense_id`, a `:not_open` error if the Book's process is not running, or another
  error if persisting fails.

  Options: `:now` and `:today` (see the moduledoc), as in `add_expense/3`.
  """
  @spec edit_expense(
          Book.id(),
          Expense.id(),
          attrs :: map(),
          opts :: keyword()
        ) ::
          {:ok, Expense.t()} | {:error, term()}
  def edit_expense(id, expense_id, attrs, opts \\ [])
      when is_binary(id) and is_binary(expense_id) and is_map(attrs) do
    opts = NimbleOptions.validate!(opts, @now_today_schema)
    BookServer.edit_expense(id, expense_id, attrs, opt_today(opts), unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Hard-deletes the Expense `expense_id` from an open Book.

  Returns a `:not_found` error for an unknown `expense_id`, a `:not_open` error if
  the Book's process is not running, or another error if persisting fails.

  Options: `:now` (see the moduledoc), which advances `updated_at`.
  """
  @spec delete_expense(Book.id(), Expense.id(), opts :: keyword()) :: :ok | {:error, term()}
  def delete_expense(id, expense_id, opts \\ [])
      when is_binary(id) and is_binary(expense_id) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.delete_expense(id, expense_id, unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Lists the expenses of an open Book.

  The list order is not a contract callers should rely on (it is not stable across
  a CRDT merge); sort in the view for display. Returns a `:not_open` error if the
  Book's process is not running (`open_book/2`), matching the mutating functions
  rather than crashing the caller.
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
  CRDT merge); sort in the view for display. Returns a `:not_open` error if the
  Book's process is not running (`open_book/2`).
  """
  @spec list_categories(Book.id()) :: [Category.t()] | {:error, :not_open}
  def list_categories(id) when is_binary(id) do
    BookServer.list_categories(id)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Returns the open Book's `Report` — its Category × Month matrix of spending totals
  (see [ADR 0020](0020-bounded-time-series-in-review.html)).

  A pure, recomputed-on-demand read model: it stamps no change and reads no clock,
  so it takes no options and mirrors `list_expenses/1`/`list_categories/1` rather
  than the command functions. Returns a `:not_open` error if the Book's process is
  not running (`open_book/2`).
  """
  @spec report(Book.id()) :: Report.t() | {:error, :not_open}
  def report(id) when is_binary(id) do
    BookServer.report(id)
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Adds a category to an open Book from a map of `attrs` (`:name`), returning the
  created `Category`.

  Returns a changeset error if `attrs` fail validation (a blank `name` — see
  `LocalCents.Tracking.Category`), a `:not_open` error if the Book's process is not
  running, or another error if persisting fails. The new Category's `id` is
  generated here (a side effect kept out of the functional core — see
  [ADR 0014](0014-functional-core-process-shell.html)).

  Options: `:now` (see the moduledoc), which advances `updated_at`.
  """
  @spec add_category(Book.id(), attrs :: map(), opts :: keyword()) ::
          {:ok, Category.t()} | {:error, term()}
  def add_category(id, attrs, opts \\ [])
      when is_binary(id) and is_map(attrs) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.add_category(id, attrs, Ecto.UUID.generate(), unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Renames the Category `category_id` in an open Book from `attrs` (`:name`),
  returning the updated `Category`.

  A rename touches only the Category — filed Expenses reference it by stable id and
  are left untouched. Returns a changeset error on invalid `attrs`, a `:not_found`
  error for an unknown `category_id`, a `:not_open` error if the Book's process is
  not running, or another error if persisting fails.

  Options: `:now` (see the moduledoc).
  """
  @spec rename_category(Book.id(), Category.id(), attrs :: map(), opts :: keyword()) ::
          {:ok, Category.t()} | {:error, term()}
  def rename_category(id, category_id, attrs, opts \\ [])
      when is_binary(id) and is_binary(category_id) and is_map(attrs) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.rename_category(id, category_id, attrs, unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Deletes the Category `category_id` from an open Book, un-filing every Expense
  filed under it so they become Uncategorized (see
  [ADR 0005](0005-categories-not-tags.html)).

  Returns a `:not_found` error for an unknown `category_id`, a `:not_open` error if
  the Book's process is not running, or another error if persisting fails.

  Options: `:now` (see the moduledoc), which advances `updated_at`.
  """
  @spec delete_category(Book.id(), Category.id(), opts :: keyword()) :: :ok | {:error, term()}
  def delete_category(id, category_id, opts \\ [])
      when is_binary(id) and is_binary(category_id) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.delete_category(id, category_id, unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Files the Expense `expense_id` under the Category `category_id` in an open Book
  (replacing any prior Category — an Expense has at most one), returning the updated
  `Expense`.

  Returns an `:expense_not_found` or `:category_not_found` error when either is
  unknown, a `:not_open` error if the Book's process is not running, or another
  error if persisting fails.

  Options: `:now` (see the moduledoc), which advances `updated_at`.
  """
  @spec assign_category(Book.id(), Expense.id(), Category.id(), opts :: keyword()) ::
          {:ok, Expense.t()} | {:error, term()}
  def assign_category(id, expense_id, category_id, opts \\ [])
      when is_binary(id) and is_binary(expense_id) and is_binary(category_id) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.assign_category(id, expense_id, category_id, unix_seconds(opt_now(opts)))
  catch
    :exit, {:noproc, _} -> {:error, :not_open}
  end

  @doc """
  Un-files the Expense `expense_id` in an open Book (nulls its `category_id` so it
  becomes Uncategorized), returning the updated `Expense`.

  Returns an `:expense_not_found` error for an unknown `expense_id`, a `:not_open`
  error if the Book's process is not running, or another error if persisting fails.

  Options: `:now` (see the moduledoc), which advances `updated_at`.
  """
  @spec unassign_category(Book.id(), Expense.id(), opts :: keyword()) ::
          {:ok, Expense.t()} | {:error, term()}
  def unassign_category(id, expense_id, opts \\ [])
      when is_binary(id) and is_binary(expense_id) do
    opts = NimbleOptions.validate!(opts, @now_schema)
    BookServer.unassign_category(id, expense_id, unix_seconds(opt_now(opts)))
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

  # The books directory an entry point operates in: the caller's injected `:books_dir`
  # option, or the platform/app-env default. Injecting a directory is what lets the
  # tracking tests run concurrently (see `docs/research/avoiding-async-false-tests.md`).
  defp opt_dir(opts), do: opts[:books_dir] || BookStore.default_dir()

  # The change clock, defaulting to now. Kept out of the `NimbleOptions` schema
  # because a schema default is captured at compile time (see the schema comment).
  defp opt_now(opts), do: opts[:now] || DateTime.utc_now()

  # The "today" date an omitted Expense date falls back to. On the desktop the server
  # and user share a machine, so the machine's local date is the user's; a future web
  # caller must pass `:today` explicitly (the server's zone is not the user's).
  defp opt_today(opts), do: opts[:today] || NaiveDateTime.to_date(NaiveDateTime.local_now())

  # The change stamp we hand the NIFs is whole unix seconds — the resolution
  # Automerge records — so a Book's `updated_at` round-trips at the same precision
  # whether it was just created or later re-read from the document.
  defp unix_seconds(%DateTime{} = now), do: DateTime.to_unix(now, :second)

  # A Book has no `updated_at` (and the library renders no "last updated" line) when
  # there's no usable stamp. We mirror the NIF's `time > 0` rule here so a freshly
  # created Book agrees with a later `list_books/1` read: `document_updated_at/1`
  # returns `nil` for an unset (`0`) stamp, so a `0` seed must become `nil` too rather
  # than the Unix epoch.
  defp to_datetime(seconds) when is_integer(seconds) and seconds > 0,
    do: DateTime.from_unix!(seconds, :second)

  defp to_datetime(_seconds), do: nil
end
