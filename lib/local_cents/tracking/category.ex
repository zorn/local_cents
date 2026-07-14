defmodule LocalCents.Tracking.Category do
  @moduledoc """
  A user-created label an Expense can be filed under — the unit a Book totals its
  spending by (see [ADR 0005](0005-categories-not-tags.html)).

  A Category has two fields:

    * `id` — a UUID assigned when the Category is created, the *stable* handle an
      Expense references it by. Because Expenses point at this id rather than the
      name, a rename never touches them and a delete un-files them by nulling the
      reference. The id is generated in the process shell and handed to the
      functional core, never by this schema (see
      [ADR 0014](0014-functional-core-process-shell.html)).
    * `name` — required, human-readable, trimmed. Free-form and user-supplied; not
      required to be unique, mirroring Book names.

  A new Book starts with an empty category list; Expenses left unfiled are
  Uncategorized (see [ADR 0005](0005-categories-not-tags.html) for that model).

  Like `LocalCents.Tracking.Expense`, this is an embedded `Ecto` schema used purely
  for casting and validation — there is no database (see
  [ADR 0016](0016-ecto-embedded-validation-no-repo.html)); the store is the Book's
  Automerge document. `changeset/2` is the single validation path shared by create
  (`add_category`) and rename (`rename_category`); the functional core
  (`LocalCents.Tracking.BookDocument`) runs it and holds the resulting struct as
  in-memory domain state.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @typedoc "A Category's identifier: a UUID string assigned at creation."
  @type id() :: String.t()

  @typedoc "A Category's human-readable name, as displayed to the user."
  @type name() :: String.t()

  @type t() :: %__MODULE__{
          id: id() | nil,
          name: name() | nil
        }

  @typedoc "An `Ecto.Changeset` over a Category, as returned by `changeset/2`."
  @type changeset() :: Ecto.Changeset.t(t())

  @primary_key false
  embedded_schema do
    field(:id, :string)
    field(:name, :string)
  end

  @doc """
  Builds the changeset that casts and validates `attrs` onto `category`.

  Shared by create and rename: for a create the caller seeds `category` with the
  freshly generated `id`; for a rename it is the existing Category, with `id`
  preserved because it is never cast. `name` is required and trimmed; a
  whitespace-only name fails `validate_required`. `attrs` may use string or atom
  keys.
  """
  @spec changeset(t(), attrs :: map()) :: changeset()
  def changeset(%__MODULE__{} = category, attrs) do
    category
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)
end
