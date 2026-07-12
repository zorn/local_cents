defmodule LocalCents.Tracking.BookStore do
  @moduledoc """
  On-disk persistence for Books: the mapping between a Book id and its `.lcbook`
  file.

  This module is the private filesystem layer of `LocalCents.Tracking`;
  `LocalCents.Tracking.BookServer` reads and writes through it.

  ## Layout

  Each Book is one Automerge document stored as a single file named
  `<book-id>.lcbook` (see [ADR 0009](0009-book-file-format.html)) inside a books
  directory. **The library is simply the enumeration of that directory** (see
  [ADR 0007](0007-book-runtime-and-persistence.html)) — there is no index or
  database.

  The books directory defaults to the platform's per-user application-support
  location (`~/Library/Application Support/LocalCents/books` on macOS) and can be
  overridden with the `:books_dir` application env, which the test suite uses to
  redirect writes to a temporary directory.
  """

  alias LocalCents.Tracking.Book

  @extension ".lcbook"

  @doc """
  Returns the directory that holds `.lcbook` files, creating it if needed.
  """
  @spec books_dir() :: String.t()
  # sobelow_skip ["Traversal.FileModule"]
  # `dir` is derived from application config or a fixed platform path, never from
  # user input, so this File call cannot be steered to traverse.
  def books_dir do
    dir =
      Application.get_env(:local_cents, :books_dir) ||
        Path.join(:filename.basedir(:user_data, "LocalCents"), "books")

    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Returns a new, random Book id (a version-4 UUID string).

  Uses `Ecto.UUID.generate/0` — the same generator as Expense ids — so Book and
  Expense ids share one scheme.
  """
  @spec generate_id() :: Book.id()
  def generate_id, do: Ecto.UUID.generate()

  @doc """
  Writes the document `bytes` for `id` to its `.lcbook` file.

  Writes to a temporary file and atomically renames it into place, so a crash or
  power loss mid-write leaves the previous `.lcbook` intact rather than a truncated,
  unreadable file. A leftover `.tmp` from an interrupted write is ignored by
  `list_ids/0` (which only matches `*.lcbook`) and is truncated and overwritten by
  the next `save/2` — writes for a given Book are serialized through its single
  `BookServer`, so two writes never race on the same `.tmp`.
  """
  @spec save(Book.id(), bytes :: binary()) :: :ok | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # Paths derive from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  # (`File.rename/2` is not a traversal sink sobelow checks.)
  def save(id, bytes) when is_binary(id) and is_binary(bytes) do
    final = path(id)
    tmp = final <> ".tmp"

    with :ok <- File.write(tmp, bytes),
         :ok <- File.rename(tmp, final) do
      :ok
    else
      {:error, reason} ->
        # A failed rename (permissions, cross-device, …) leaves the temp file
        # behind; remove it so errors don't accumulate stale `.tmp` files. Ignore
        # the cleanup result — the original error is what the caller needs.
        _ = File.rm(tmp)
        {:error, reason}
    end
  end

  @doc """
  Reads the document bytes for `id`.
  """
  @spec load(Book.id()) :: {:ok, binary()} | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  def load(id) when is_binary(id) do
    File.read(path(id))
  end

  @doc """
  Deletes the `.lcbook` file for `id`.
  """
  @spec delete(Book.id()) :: :ok | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  def delete(id) when is_binary(id) do
    File.rm(path(id))
  end

  @doc """
  Returns the ids of every Book with a `.lcbook` file in the books directory.
  """
  @spec list_ids() :: [Book.id()]
  def list_ids do
    [books_dir(), "*" <> @extension]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, @extension))
  end

  @doc """
  Returns the absolute path of the `.lcbook` file for `id`.

  Raises `ArgumentError` unless `id` is a single, safe path component. Book ids
  will eventually arrive from request params (the `/books/:id` route), so this is
  the chokepoint that keeps a hostile id (e.g. `"../secrets"`) from escaping the
  books directory. `Path.basename(id) == id` rejects anything containing a
  directory separator or a `.`/`..` segment.
  """
  @spec path(Book.id()) :: String.t()
  def path(id) when is_binary(id) do
    Path.join(books_dir(), safe_component!(id) <> @extension)
  end

  defp safe_component!(id) do
    cond do
      id == "" or id in [".", ".."] ->
        raise ArgumentError, "unsafe book id: #{inspect(id)}"

      Path.basename(id) != id ->
        raise ArgumentError, "unsafe book id: #{inspect(id)}"

      true ->
        id
    end
  end
end
