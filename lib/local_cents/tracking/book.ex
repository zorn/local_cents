defmodule LocalCents.Tracking.Book do
  @moduledoc """
  The library-facing identity of a Book: its `id` and human-readable `name`.

  A Book's authoritative state is an Automerge document owned by a
  `LocalCents.Tracking.BookServer` process and persisted as a `.lcbook` file. This
  struct is the lightweight value the `LocalCents.Tracking` API hands back so
  callers can list and refer to Books without touching those internals. The `id`
  is the file name (a UUID); the `name` is read from inside the document (see
  [ADR 0007](0007-book-runtime-and-persistence.html)).
  """

  @enforce_keys [:id, :name]
  defstruct id: nil, name: nil

  @type t() :: %__MODULE__{
          id: String.t(),
          name: String.t()
        }
end
