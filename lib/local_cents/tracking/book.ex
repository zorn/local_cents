defmodule LocalCents.Tracking.Book do
  @moduledoc """
  The library-facing view of a Book: its `id`, human-readable `name`, and
  `updated_at`.

  A Book's authoritative state is an Automerge document owned by a
  `LocalCents.Tracking.BookServer` process and persisted as a `.lcbook` file. This
  struct is the lightweight value the `LocalCents.Tracking` API hands back so
  callers can list and refer to Books without touching those internals. The `id`
  is the file name (a UUID); the `name` is read from inside the document (see
  [ADR 0007](0007-book-runtime-and-persistence.html)); `updated_at` is derived from
  the document's change history (see
  [ADR 0012](0012-book-last-updated-timestamp.html)) so the library can show a
  "last updated" that survives sync.
  """

  @enforce_keys [:id, :name]
  defstruct id: nil, name: nil, updated_at: nil

  @typedoc """
  A Book's unique identifier: a UUID string that is also its `.lcbook` file name.
  """
  @type id() :: String.t()

  @typedoc """
  A Book's human-readable name, as shown in the library and displayed to the user.
  Free-form and user-supplied; not required to be unique.
  """
  @type name() :: String.t()

  @typedoc """
  When the Book was last changed, in UTC, or `nil` if the document carries no
  usable change time. Derived from the Automerge document's change history — the
  time of the most recent edit at its heads — rather than the `.lcbook` file's
  mtime, so it reflects the latest edit through sync (see
  [ADR 0012](0012-book-last-updated-timestamp.html)). Callers localize and format
  it for display.
  """
  @type updated_at() :: DateTime.t() | nil

  @type t() :: %__MODULE__{
          id: id(),
          name: name(),
          updated_at: updated_at()
        }
end
