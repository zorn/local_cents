defmodule LocalCents.Tracking.BookDocument do
  @moduledoc """
  The functional core of a Book: its decoded contents (name + expenses) as plain
  Elixir data, plus every domain command that mutates them — all as pure functions.

  This is the "functional core" half of the functional-core / process-shell split
  (see [ADR 0014](0014-functional-core-process-shell.html)). It holds no process
  state, performs no I/O, and reads no clock: commands take everything they need —
  an injected `id`, an injected `today`, the attributes — as arguments and return a
  new `BookDocument` plus a result or an error. That makes the whole domain model
  testable as plain data, with no GenServer and no NIF.

  The process shell (`LocalCents.Tracking.BookServer`) wraps each command with the
  side effects: it `decode`s the document bytes into a `BookDocument`, runs the
  command, and — on success — `apply`s the new state back to bytes, persists, and
  broadcasts. The CRDT codec lives in `LocalCents.Tracking.ExAutomerge`; `from_raw/1`
  and `to_raw/1` here translate between that codec's raw string maps and the typed
  domain state (`date` as a `Date`, `cost` as a `Decimal`).

  Expenses are addressed by their `id` (see
  [ADR 0015](0015-expense-identity-and-date-encoding.html)), never by position, so
  edits and deletes are stable across a CRDT merge. Expenses are kept in insertion
  order; presentation ordering (e.g. sorting by date) is a view concern, not the
  model's.
  """

  import Ecto.Changeset, only: [apply_action: 2]

  alias LocalCents.Tracking.ExAutomerge
  alias LocalCents.Tracking.Expense

  @enforce_keys [:name]
  defstruct name: nil, expenses: []

  @type t() :: %__MODULE__{
          name: String.t(),
          expenses: [Expense.t()]
        }

  @doc """
  Decodes document bytes straight into a `BookDocument`.

  The read half of the codec bridge: `ExAutomerge.decode/1` then `from_raw/1`, so
  the process shell deals only in domain values and never touches the codec module
  directly.
  """
  @spec from_bytes(binary()) :: t()
  def from_bytes(bytes), do: from_raw(ExAutomerge.decode(bytes))

  @doc """
  Encodes this document onto `prior_bytes`, returning the new bytes.

  The write half of the codec bridge: `to_raw/1` then `ExAutomerge.reconcile/3`.
  `time` (unix seconds) stamps the resulting change.
  """
  @spec to_bytes(t(), binary(), integer()) :: binary()
  def to_bytes(%__MODULE__{} = document, prior_bytes, time) do
    ExAutomerge.reconcile(prior_bytes, to_raw(document), time)
  end

  @doc """
  Builds a `BookDocument` from the raw state map produced by
  `LocalCents.Tracking.ExAutomerge.decode/1`, parsing each expense's stored `date`
  string into a `Date` and `cost` string into a `Decimal` (`nil` stays `nil`).
  """
  @spec from_raw(ExAutomerge.state()) :: t()
  def from_raw(%{name: name, expenses: raw_expenses}) do
    %__MODULE__{name: name, expenses: Enum.map(raw_expenses, &expense_from_raw/1)}
  end

  @doc """
  Renders a `BookDocument` back to the raw state map
  `LocalCents.Tracking.ExAutomerge.reconcile/3` expects, encoding each expense's `date`
  as an ISO-8601 string and `cost` as a decimal string (`nil` stays `nil`).
  """
  @spec to_raw(t()) :: ExAutomerge.state()
  def to_raw(%__MODULE__{name: name, expenses: expenses}) do
    %{name: name, expenses: Enum.map(expenses, &expense_to_raw/1)}
  end

  @doc """
  Returns the document's expenses, in insertion order.
  """
  @spec expenses(t()) :: [Expense.t()]
  def expenses(%__MODULE__{expenses: expenses}), do: expenses

  @doc """
  Appends a new Expense built from `attrs`, using the injected `id` and defaulting a
  blank `date` to `today`.

  Returns `{:ok, document, expense}` with the created Expense, or
  `{:error, changeset}` if `attrs` fail validation.
  """
  @spec add_expense(t(), map(), Expense.id(), Date.t()) ::
          {:ok, t(), Expense.t()} | {:error, Ecto.Changeset.t()}
  def add_expense(%__MODULE__{} = document, attrs, id, %Date{} = today) do
    changeset = Expense.changeset(%Expense{id: id}, attrs, today)

    case apply_action(changeset, :insert) do
      {:ok, expense} ->
        {:ok, %{document | expenses: List.insert_at(document.expenses, -1, expense)}, expense}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Replaces every editable field of the Expense identified by `id` with `attrs` (a
  full replace, not a patch), defaulting a blank `date` to `today`. The `id` is
  preserved.

  Returns `{:ok, document, expense}` with the updated Expense, `{:error, changeset}`
  on invalid `attrs`, or `{:error, :not_found}` if no Expense has that `id`.
  """
  @spec edit_expense(t(), Expense.id(), map(), Date.t()) ::
          {:ok, t(), Expense.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  def edit_expense(%__MODULE__{} = document, id, attrs, %Date{} = today) do
    case Enum.find_index(document.expenses, &(&1.id == id)) do
      nil ->
        {:error, :not_found}

      index ->
        existing = Enum.at(document.expenses, index)
        changeset = Expense.changeset(existing, attrs, today)

        case apply_action(changeset, :update) do
          {:ok, expense} ->
            {:ok, %{document | expenses: List.replace_at(document.expenses, index, expense)},
             expense}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Hard-deletes the Expense identified by `id`.

  Returns `{:ok, document}`, or `{:error, :not_found}` if no Expense has that `id`.
  """
  @spec delete_expense(t(), Expense.id()) :: {:ok, t()} | {:error, :not_found}
  def delete_expense(%__MODULE__{} = document, id) do
    case Enum.split_with(document.expenses, &(&1.id == id)) do
      {[], _kept} -> {:error, :not_found}
      {_removed, kept} -> {:ok, %{document | expenses: kept}}
    end
  end

  @doc """
  Sets the Book's name. Returns `{:ok, document}`.
  """
  @spec rename(t(), String.t()) :: {:ok, t()}
  def rename(%__MODULE__{} = document, new_name) when is_binary(new_name) do
    {:ok, %{document | name: new_name}}
  end

  defp expense_from_raw(%{id: id, date: date, description: description, cost: cost}) do
    %Expense{
      id: id,
      date: Date.from_iso8601!(date),
      description: description,
      cost: parse_cost(cost)
    }
  end

  defp parse_cost(nil), do: nil
  defp parse_cost(cost) when is_binary(cost), do: Decimal.new(cost)

  defp expense_to_raw(%Expense{id: id, date: date, description: description, cost: cost}) do
    %{id: id, date: Date.to_iso8601(date), description: description, cost: dump_cost(cost)}
  end

  defp dump_cost(nil), do: nil
  defp dump_cost(%Decimal{} = cost), do: Decimal.to_string(cost, :normal)
end
