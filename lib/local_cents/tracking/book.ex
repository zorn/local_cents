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

  @typedoc """
  A Book's unique identifier: a UUID string that is also its `.lcbook` file name.
  """
  @type id() :: String.t()

  @typedoc """
  A Book's human-readable name, as shown in the library and displayed to the user.
  Free-form and user-supplied; not required to be unique.
  """
  @type name() :: String.t()

  @type t() :: %__MODULE__{
          id: id(),
          name: name()
        }
end
