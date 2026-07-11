defmodule LocalCents.Tracking.Expense do
  @moduledoc """
  A financial transaction that represents money the user has spent — the core
  entry a Book records.

  An Expense has four fields (see [ADR 0008](0008-mvp-expense-shape.html)):

    * `id` — a UUID assigned when the Expense is created, used to address it for
      edits and deletes so those survive a CRDT merge (see
      [ADR 0015](0015-expense-identity-and-date-encoding.html)). The id is
      generated in the process shell and handed to the functional core, never by
      this schema.
    * `date` — the calendar day the money was spent; required, defaults to *today*
      when left blank. "Today" is supplied by the caller, never read from a clock
      here, so the value is correct for the user's timezone rather than the
      server's (see [ADR 0014](0014-functional-core-process-shell.html)).
    * `description` — required, human-readable.
    * `cost` — optional and `nil` when unknown, **never defaulted to zero**; a
      genuine `0` is distinct from "not yet entered." When present it must be
      non-negative — refunds/credits/income are out of MVP scope. Stored as a
      decimal string and handled with `Decimal` (see
      [ADR 0010](0010-cost-as-decimal-string.html)).

  This is an embedded `Ecto` schema used purely for casting and validation — there
  is no database (see [ADR 0016](0016-ecto-embedded-validation-no-repo.html)); the
  store is the Book's Automerge document. `changeset/3` is the single validation
  path shared by create and edit; the functional core
  (`LocalCents.Tracking.BookDocument`) runs it and, on success, holds the resulting
  struct as in-memory domain state (`date` as a `Date`, `cost` as a `Decimal`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @typedoc "An Expense's identifier: a UUID string assigned at creation."
  @type id() :: String.t()

  @type t() :: %__MODULE__{
          id: id() | nil,
          date: Date.t() | nil,
          description: String.t() | nil,
          cost: Decimal.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:id, :string)
    field(:date, :date)
    field(:description, :string)
    field(:cost, :decimal)
  end

  @cast_fields [:date, :description, :cost]

  @doc """
  Casts and validates `attrs` onto `expense`, defaulting a blank `date` to `today`.

  Shared by create and edit: for a create the caller seeds `expense` with the
  freshly generated `id`; for an edit it is the existing Expense, and every
  editable field is replaced (a full replace, not a patch — see the editor design),
  with `id` preserved because it is never cast.

  Rules enforced: `date` and `description` are required (a blank `date` becomes
  `today` rather than an error); `cost` is optional and, when present, must be
  non-negative (`0` is allowed). `attrs` may use string or atom keys; a blank
  string for `date` or `cost` is treated as absent.
  """
  @spec changeset(t(), attrs :: map(), today :: Date.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = expense, attrs, %Date{} = today) do
    expense
    |> cast(normalize(attrs), @cast_fields)
    |> default_date(today)
    |> update_change(:description, &trim/1)
    |> validate_required([:date, :description])
    |> validate_number(:cost,
      greater_than_or_equal_to: 0,
      message: "must be zero or greater"
    )
  end

  # Form params arrive with string keys and empty strings for untouched fields.
  # Normalize to string keys and turn any blank string into `nil` — an explicit
  # *clear*, not a "leave unchanged". That is what makes this a full replace: a
  # blank date then picks up the `today` default, a blank cost becomes `nil` (never
  # `0`, per ADR 0008), and a blank description fails `validate_required`. Passing a
  # blank string straight to `cast` would instead raise an "is invalid" error on the
  # typed `date`/`cost` fields.
  defp normalize(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), blank_to_nil(value)} end)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      _ -> value
    end
  end

  defp blank_to_nil(value), do: value

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp default_date(changeset, today) do
    case get_field(changeset, :date) do
      nil -> put_change(changeset, :date, today)
      _date -> changeset
    end
  end
end
