defmodule LocalCents.Tracking.ExAutomerge do
  @moduledoc """
  The Rust bridge that backs the tracking context with an [Automerge](https://automerge.org)
  CRDT document.

  This module is the private implementation of `LocalCents.Tracking`. It is
  **not** part of the tracking boundary's public API — nothing outside the
  context should call it directly (the `Boundary` compiler enforces this). It is
  documented here for maintainers who need to understand how books are stored and
  merged; see [Module Boundaries](module-boundaries.html) for the rules.

  ## How it works

  Every function is a [Rustler](https://hexdocs.pm/rustler) NIF implemented in the
  `ex_automerge` crate (see `native/ex_automerge`). An Automerge document is
  represented on the Elixir side as an **opaque binary** — the serialized bytes of
  the CRDT. We never inspect or build these bytes in Elixir; we pass them back into
  the NIFs.

  Each document is a single LocalCents Book: it carries the Book's human-readable
  `name` alongside its list of expenses (see
  [ADR 0007](0007-book-runtime-and-persistence.html), which places the name *inside*
  the document while the Book id lives in the file name). `document_name/1` reads
  that name back out — the library uses it to enumerate Books without starting a
  process per file.

  Every mutating NIF (`new_document/2`, `rename/3`, `add_expense/4`) takes a
  `time` — a unix-seconds stamp Elixir supplies — and records it on the Automerge
  change it produces. `document_updated_at/1` reads the most recent such stamp back
  out, which is how a Book earns its "last updated" without relying on the file's
  mtime (see [ADR 0012](0012-book-last-updated-timestamp.html)). The Automerge core
  never defaults a change time, so the clock stays in Elixir and is always passed
  in explicitly.

  Because the document is a CRDT, two independently edited copies can be combined
  with `merge/2` without conflicts, which is the foundation for future
  multi-device sync.

  The function bodies below call `:erlang.nif_error/1`; that is only a fallback
  raised if the native library failed to load. At runtime the Rust
  implementations replace them.
  """

  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  @doc """
  Creates a new, empty Automerge document for a Book named `name` and returns its
  serialized bytes.

  `time` is a unix-seconds timestamp recorded on the document's first change so the
  Book has a "last updated" from the moment it exists.
  """
  @spec new_document(name :: String.t(), time :: integer()) :: binary()
  def new_document(_name, _time), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the Book name stored in the document.
  """
  @spec document_name(doc_bytes :: binary()) :: String.t()
  def document_name(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the unix-seconds timestamp of the document's most recent change, or `nil`
  when no change carries a usable time.

  Derived from Automerge change metadata (the max across the document's changes)
  rather than a stored field, so it reflects the *latest edit* after a merge rather
  than the latest local write (see [ADR 0012](0012-book-last-updated-timestamp.html)).
  """
  @spec document_updated_at(doc_bytes :: binary()) :: integer() | nil
  def document_updated_at(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Sets the Book name and returns the updated serialized bytes.

  `time` is a unix-seconds timestamp recorded on the resulting change. The document
  is never mutated in place — a new binary is returned.
  """
  @spec rename(doc_bytes :: binary(), name :: String.t(), time :: integer()) :: binary()
  def rename(_doc_bytes, _name, _time), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Appends an expense to the document and returns the updated serialized bytes.

  Takes the current document bytes, a `description`, an `amount`, and a `time` (unix
  seconds) recorded on the resulting change, and returns a new binary — the document
  is never mutated in place.
  """
  @spec add_expense(
          doc_bytes :: binary(),
          description :: String.t(),
          amount :: number(),
          time :: integer()
        ) :: binary()
  def add_expense(_doc_bytes, _description, _amount, _time),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the expenses stored in the document as a list of plain maps.

  Each map has `:description` and `:amount` keys. `LocalCents.Tracking` maps these
  into `LocalCents.Tracking.Expense` structs before handing them to callers.
  """
  @spec list_expenses(doc_bytes :: binary()) :: [map()]
  def list_expenses(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Merges two documents into one and returns the combined serialized bytes.

  Automerge resolves the two histories as a CRDT, so the operation is safe even
  when both sides were edited independently.
  """
  @spec merge(left_bytes :: binary(), right_bytes :: binary()) :: binary()
  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
