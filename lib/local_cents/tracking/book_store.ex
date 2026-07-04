defmodule LocalCents.Tracking.BookStore do
  @moduledoc """
  On-disk persistence for Books: the mapping between a Book id and its `.lcbook`
  file.

  This module is the private filesystem layer of `LocalCents.Tracking`. Nothing
  outside the context should call it directly (the `Boundary` compiler enforces
  this); `LocalCents.Tracking.BookServer` reads and writes through it.

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

  We generate this ourselves rather than pull in a UUID dependency; the value only
  needs to be a collision-resistant, filesystem-safe file name.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    # Set the version (4) and variant (RFC 4122) bits.
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    formatted = :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    IO.iodata_to_binary(formatted)
  end

  @doc """
  Writes the document `bytes` for `id` to its `.lcbook` file.

  Writes to a temporary file and atomically renames it into place, so a crash or
  power loss mid-write leaves the previous `.lcbook` intact rather than a truncated,
  unreadable file. A leftover `.tmp` from an interrupted write is ignored by
  `list_ids/0` (which only matches `*.lcbook`).
  """
  @spec save(String.t(), binary()) :: :ok | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # Paths derive from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  # (`File.rename/2` is not a traversal sink sobelow checks.)
  def save(id, bytes) when is_binary(id) and is_binary(bytes) do
    final = path(id)
    tmp = final <> ".tmp"

    with :ok <- File.write(tmp, bytes) do
      File.rename(tmp, final)
    end
  end

  @doc """
  Reads the document bytes for `id`.
  """
  @spec load(String.t()) :: {:ok, binary()} | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  def load(id) when is_binary(id) do
    File.read(path(id))
  end

  @doc """
  Deletes the `.lcbook` file for `id`.
  """
  @spec delete(String.t()) :: :ok | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from `path/1`, which raises unless `id` is a single safe path
  # component — a hostile id (e.g. "../secrets") cannot escape the books directory.
  def delete(id) when is_binary(id) do
    File.rm(path(id))
  end

  @doc """
  Returns the ids of every Book with a `.lcbook` file in the books directory.
  """
  @spec list_ids() :: [String.t()]
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
  @spec path(String.t()) :: String.t()
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
