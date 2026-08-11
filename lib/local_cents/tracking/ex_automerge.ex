defmodule LocalCents.Tracking.ExAutomerge do
  @moduledoc """
  The Rust bridge that stores the tracking context's data as an
  [Automerge](https://automerge.org) CRDT document. It only **encodes and decodes**
  those documents — and merges them — holding no domain logic of its own.

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

  Each document is a single LocalCents Book. Its decoded contents are the Book's
  human-readable `name` plus its lists of categories and expenses (see
  [ADR 0007](0007-book-runtime-and-persistence.html), which places the name
  *inside* the document while the Book id lives in the file name).

  ## Encode and decode, no domain logic

  This module deliberately owns **no domain rules** (see
  [ADR 0014](0014-functional-core-process-shell.html)). It is just the two halves
  of an encode/decode round-trip between document bytes and the _raw_ state map the
  functional core works on:

    * `decode/1` turns document bytes into the raw state map
      (`%{name:, categories:, expenses:}`, see `t:state/0`) that the functional core
      (`LocalCents.Tracking.BookDocument`) reasons about, and
    * `reconcile/3` takes a whole *new* raw state the core has computed and
      reconciles it onto the prior bytes, returning the new bytes.

  There is a single mutation path — `reconcile/3`. Adding, editing, or deleting an
  expense or a category, filing an expense under a category, and renaming the Book
  are all just "compute a new state and apply it"; Rust records the minimal
  Automerge operations by diffing the two.

  Every mutating call (`new_document/2`, `reconcile/3`) takes a `time` — a unix-seconds
  stamp Elixir supplies — and records it on the Automerge change it produces.
  `document_updated_at/1` reads the most recent such stamp back out, which is how a
  Book earns its "last updated" without relying on the file's mtime (see
  [ADR 0012](0012-book-last-updated-timestamp.html)). The Automerge core never
  defaults a change time, so the clock stays in Elixir and is always passed in
  explicitly.

  Because the document is a CRDT, `merge/2` always combines two independently edited
  copies without failing, resolving their histories deterministically — concurrent
  writes to the same field are kept as conflicting values, not silently dropped.
  `merge/2` ships the whole document, so it is the way to combine two copies, not the
  sync transport. The delta-based transport is the
  sync protocol — `new_sync_state/0`, `generate_sync_message/2` and
  `receive_sync_message/3` — which sends only the changes the remote is missing (see
  `t:sync_state/0` and [ADR 0025](0025-two-peer-sync-architecture.html)).

  The function bodies below call `:erlang.nif_error/1`; that is only a fallback
  raised if the native library failed to load. At runtime the Rust
  implementations replace them.
  """

  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  @typedoc """
  The decoded contents of a Book document in _raw_ form: the Book `name` (a string),
  its list of raw category maps (`t:raw_category/0`) and its list of raw expense maps
  (`t:raw_expense/0` — atom keys, string values). This is the shape `decode/1`
  returns and `reconcile/3` accepts; `LocalCents.Tracking.BookDocument` parses it
  into typed domain values.
  """
  @type state() :: %{
          name: String.t(),
          categories: [raw_category()],
          expenses: [raw_expense()]
        }

  @typedoc """
  One category as stored in the document: a stable `id` and a user-facing `name`,
  both strings (see ADR 0005).
  """
  @type raw_category() :: %{id: String.t(), name: String.t()}

  @typedoc """
  One expense as stored in the document: all string values, with `cost` `nil` when
  absent (the decimal string otherwise) and `category_id` `nil` when Uncategorized
  (the referenced Category's `id` otherwise). `date` is an ISO-8601 date string.
  """
  @type raw_expense() :: %{
          id: String.t(),
          date: String.t(),
          description: String.t(),
          cost: String.t() | nil,
          category_id: String.t() | nil
        }

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

  A lightweight read for the library enumeration, which needs only the name and
  not the (potentially large) expense list.
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
  Decodes the document bytes into the raw `t:state/0` map the functional core
  parses into domain values. The read half of the round-trip; it never mutates.
  """
  @spec decode(doc_bytes :: binary()) :: state()
  def decode(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Reconciles a whole `new_state` onto `prior_bytes` and returns the updated bytes.
  The single mutation path (write half of the codec).

  The functional core (`LocalCents.Tracking.BookDocument`) computes `new_state` in
  domain terms — an added/edited/deleted expense or a renamed Book — and hands it
  here. Loading the prior document first preserves the change history, and
  `time` (unix seconds) stamps the resulting change. The document is never mutated
  in place — a new binary is returned.
  """
  @spec reconcile(prior_bytes :: binary(), new_state :: state(), time :: integer()) :: binary()
  def reconcile(_prior_bytes, _new_state, _time), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Merges two documents into one and returns the combined serialized bytes.

  Automerge resolves the two histories as a CRDT, so the operation is safe even
  when both sides were edited independently.
  """
  @spec merge(left_bytes :: binary(), right_bytes :: binary()) :: binary()
  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @typedoc """
  A per-peer sync `State` as an opaque, mutable handle (a NIF resource reference).

  Each peer keeps one **per remote peer** it talks to; the handle remembers what the
  two sides have exchanged, so a later reconcile ships only the missing changes. It is
  a live handle rather than bytes because Automerge serializes only the cross-session
  part of a sync `State` and drops the in-session progress needed to avoid re-sending.
  So `generate_sync_message/2` and `receive_sync_message/3` mutate it in place, and it
  belongs to one connection and is never sent over the wire — only the messages are.
  """
  @type sync_state() :: reference()

  @doc """
  Returns a fresh, empty per-peer sync `t:sync_state/0`.

  A peer creates one of these for each remote peer it reconciles with, then
  drives the exchange by alternating `generate_sync_message/2` and
  `receive_sync_message/3` until both sides have nothing left to send.
  """
  @spec new_sync_state() :: sync_state()
  def new_sync_state, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the next sync message `doc_bytes` needs to send the remote peer that
  `sync_state` tracks, or `nil` when there is nothing to send, and advances
  `sync_state` in place.

  The message carries only the changes the remote is missing. A `nil` message means
  the remote is up to date or we are waiting for it to acknowledge an in-flight
  message — the handle still advances, so the caller reuses it on the next call.
  """
  @spec generate_sync_message(doc_bytes :: binary(), sync_state()) :: binary() | nil
  def generate_sync_message(_doc_bytes, _sync_state), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Applies an inbound sync `message` to `doc_bytes`, folding in the changes it
  carries, returns the updated document bytes, and advances `sync_state` in place.

  The write half of the sync exchange: `generate_sync_message/2` on one peer
  produces the `message`, this receives it on the other. Reconciling two
  divergent documents is a loop of generate-then-receive on each side until both
  `generate_sync_message/2` calls return `nil`.
  """
  @spec receive_sync_message(
          doc_bytes :: binary(),
          sync_state(),
          message :: binary()
        ) :: binary()
  def receive_sync_message(_doc_bytes, _sync_state, _message),
    do: :erlang.nif_error(:nif_not_loaded)
end
