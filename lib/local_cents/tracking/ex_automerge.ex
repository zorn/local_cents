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
  the NIFs. `LocalCents.Tracking` wraps that binary in a `LocalCents.Tracking.Book`
  struct so the rest of the app deals in domain terms rather than raw bytes.

  Because the document is a CRDT, two independently edited copies can be combined
  with `merge/2` without conflicts, which is the foundation for future
  multi-device sync.

  The function bodies below call `:erlang.nif_error/1`; that is only a fallback
  raised if the native library failed to load. At runtime the Rust
  implementations replace them.
  """

  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  @doc """
  Creates a new, empty Automerge document and returns its serialized bytes.
  """
  @spec new_document() :: binary()
  def new_document, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Appends an expense to the document and returns the updated serialized bytes.

  Takes the current document bytes, a `description`, and an `amount`, and returns
  a new binary — the document is never mutated in place.
  """
  @spec add_expense(binary(), String.t(), number()) :: binary()
  def add_expense(_doc_bytes, _description, _amount),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the expenses stored in the document as a list of plain maps.

  Each map has `:description` and `:amount` keys. `LocalCents.Tracking` maps these
  into `LocalCents.Tracking.Expense` structs before handing them to callers.
  """
  @spec list_expenses(binary()) :: [map()]
  def list_expenses(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Merges two documents into one and returns the combined serialized bytes.

  Automerge resolves the two histories as a CRDT, so the operation is safe even
  when both sides were edited independently.
  """
  @spec merge(binary(), binary()) :: binary()
  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
