defmodule LocalCents.Tracking.BookDocument do
  @moduledoc """
  The functional core of a Book: its decoded contents (name + categories + expenses)
  as plain Elixir data, plus every domain command that mutates them — all as pure
  functions.

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

  Expenses and categories alike are addressed by their `id` (see
  [ADR 0015](0015-expense-identity-and-date-encoding.html)), never by position, so
  edits and deletes are stable across a CRDT merge. Both lists are kept in insertion
  order; presentation ordering (e.g. sorting by date) is a view concern, not the
  model's.

  An Expense is filed under at most one Category by its `category_id` (see
  [ADR 0005](0005-categories-not-tags.html)). Referencing the Category by stable id
  is what keeps the two independent: `rename_category` rewrites only the Category,
  and `delete_category` un-files affected Expenses by nulling their `category_id`
  (they become Uncategorized — a computed absence, never a record).
  """

  import Ecto.Changeset, only: [apply_action: 2]

  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.ExAutomerge
  alias LocalCents.Tracking.Expense

  @enforce_keys [:name]
  defstruct name: nil, categories: [], expenses: []

  @type t() :: %__MODULE__{
          name: String.t(),
          categories: [Category.t()],
          expenses: [Expense.t()]
        }

  @doc """
  Decodes document bytes straight into a `BookDocument`.

  The read half of the codec bridge: `ExAutomerge.decode/1` then `from_raw/1`, so
  the process shell deals only in domain values and never touches the codec module
  directly.
  """
  @spec from_bytes(doc_bytes :: binary()) :: t()
  def from_bytes(bytes), do: from_raw(ExAutomerge.decode(bytes))

  @doc """
  Encodes this document onto `prior_bytes`, returning the new bytes.

  The write half of the codec bridge: `to_raw/1` then `ExAutomerge.reconcile/3`.
  `time` (unix seconds) stamps the resulting change.
  """
  @spec to_bytes(t(), prior_bytes :: binary(), time :: integer()) :: binary()
  def to_bytes(%__MODULE__{} = document, prior_bytes, time) do
    ExAutomerge.reconcile(prior_bytes, to_raw(document), time)
  end

  @doc """
  Reads only the Book's name from document `doc_bytes`, without decoding the whole
  document. Cheaper and more robust than `from_bytes/1` when only the name is
  needed, since it does not parse the expenses.
  """
  @spec name(doc_bytes :: binary()) :: String.t()
  def name(doc_bytes), do: ExAutomerge.document_name(doc_bytes)

  @doc """
  Builds a `BookDocument` from the raw state map produced by
  `LocalCents.Tracking.ExAutomerge.decode/1`, parsing each category into a
  `Category` and each expense's stored `date` string into a `Date` and `cost`
  string into a `Decimal` (`nil` stays `nil`).
  """
  @spec from_raw(ExAutomerge.state()) :: t()
  def from_raw(%{name: name, categories: raw_categories, expenses: raw_expenses}) do
    %__MODULE__{
      name: name,
      categories: Enum.map(raw_categories, &category_from_raw/1),
      expenses: Enum.map(raw_expenses, &expense_from_raw/1)
    }
  end

  @doc """
  Renders a `BookDocument` back to the raw state map
  `LocalCents.Tracking.ExAutomerge.reconcile/3` expects, encoding each expense's `date`
  as an ISO-8601 string and `cost` as a decimal string (`nil` stays `nil`) and each
  category as its raw map.
  """
  @spec to_raw(t()) :: ExAutomerge.state()
  def to_raw(%__MODULE__{name: name, categories: categories, expenses: expenses}) do
    %{
      name: name,
      categories: Enum.map(categories, &category_to_raw/1),
      expenses: Enum.map(expenses, &expense_to_raw/1)
    }
  end

  @doc """
  Returns the document's expenses.

  The list follows the order stored in the document; that order is **not** a
  contract callers should rely on (it is not stable across a CRDT merge).
  Presentation ordering — e.g. sorting by date — is the view's concern.
  """
  @spec expenses(t()) :: [Expense.t()]
  def expenses(%__MODULE__{expenses: expenses}), do: expenses

  @doc """
  Returns the document's categories, in insertion order.

  As with expenses, that order is **not** stable across a CRDT merge; the
  management view sorts for display.
  """
  @spec categories(t()) :: [Category.t()]
  def categories(%__MODULE__{categories: categories}), do: categories

  @doc """
  Appends a new Expense built from `attrs`, using the injected `id` and defaulting a
  blank `date` to `today`.

  Returns `{:ok, document, expense}` with the created Expense, or
  `{:error, changeset}` if `attrs` fail validation.
  """
  @spec add_expense(t(), attrs :: map(), Expense.id(), today :: Date.t()) ::
          {:ok, t(), Expense.t()} | {:error, Expense.changeset()}
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
  @spec edit_expense(t(), Expense.id(), attrs :: map(), today :: Date.t()) ::
          {:ok, t(), Expense.t()} | {:error, Expense.changeset()} | {:error, :not_found}
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
  @spec rename(t(), new_name :: String.t()) :: {:ok, t()}
  def rename(%__MODULE__{} = document, new_name) when is_binary(new_name) do
    {:ok, %{document | name: new_name}}
  end

  @doc """
  Appends a new Category built from `attrs`, using the injected `id`.

  Returns `{:ok, document, category}` with the created Category, or
  `{:error, changeset}` if `attrs` fail validation (a blank `name`).
  """
  @spec add_category(t(), attrs :: map(), Category.id()) ::
          {:ok, t(), Category.t()} | {:error, Category.changeset()}
  def add_category(%__MODULE__{} = document, attrs, id) do
    changeset = Category.changeset(%Category{id: id}, attrs)

    case apply_action(changeset, :insert) do
      {:ok, category} ->
        {:ok, %{document | categories: List.insert_at(document.categories, -1, category)},
         category}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Renames the Category identified by `id` from `attrs` (only its `name`; the `id` is
  preserved).

  A rename touches only the Category — Expenses reference it by stable `id`, so
  their `category_id` is left untouched. Returns `{:ok, document, category}` with the
  updated Category, `{:error, changeset}` on invalid `attrs`, or
  `{:error, :not_found}` if no Category has that `id`.
  """
  @spec rename_category(t(), Category.id(), attrs :: map()) ::
          {:ok, t(), Category.t()}
          | {:error, Category.changeset()}
          | {:error, :not_found}
  def rename_category(%__MODULE__{} = document, id, attrs) do
    case Enum.find_index(document.categories, &(&1.id == id)) do
      nil ->
        {:error, :not_found}

      index ->
        existing = Enum.at(document.categories, index)
        changeset = Category.changeset(existing, attrs)

        case apply_action(changeset, :update) do
          {:ok, category} ->
            {:ok, %{document | categories: List.replace_at(document.categories, index, category)},
             category}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Deletes the Category identified by `id` and un-files every Expense filed under it,
  nulling their `category_id` so they become Uncategorized (see
  [ADR 0005](0005-categories-not-tags.html)).

  Returns `{:ok, document}`, or `{:error, :not_found}` if no Category has that `id`.
  """
  @spec delete_category(t(), Category.id()) :: {:ok, t()} | {:error, :not_found}
  def delete_category(%__MODULE__{} = document, id) do
    case Enum.split_with(document.categories, &(&1.id == id)) do
      {[], _kept} ->
        {:error, :not_found}

      {_removed, kept} ->
        {:ok, %{document | categories: kept, expenses: unfile_expenses(document.expenses, id)}}
    end
  end

  @doc """
  Files the Expense `expense_id` under the Category `category_id`, replacing any
  prior Category (an Expense has at most one — see
  [ADR 0005](0005-categories-not-tags.html)).

  Both must exist: returns `{:ok, document, expense}` with the updated Expense,
  `{:error, :expense_not_found}` for an unknown `expense_id`, or
  `{:error, :category_not_found}` for an unknown `category_id`.
  """
  @spec assign_category(t(), Expense.id(), Category.id()) ::
          {:ok, t(), Expense.t()} | {:error, :expense_not_found} | {:error, :category_not_found}
  def assign_category(%__MODULE__{} = document, expense_id, category_id) do
    cond do
      not Enum.any?(document.expenses, &(&1.id == expense_id)) ->
        {:error, :expense_not_found}

      not Enum.any?(document.categories, &(&1.id == category_id)) ->
        {:error, :category_not_found}

      true ->
        set_expense_category(document, expense_id, category_id)
    end
  end

  @doc """
  Un-files the Expense `expense_id`, nulling its `category_id` so it becomes
  Uncategorized.

  Returns `{:ok, document, expense}` with the updated Expense, or
  `{:error, :expense_not_found}` for an unknown `expense_id`. Un-filing an already
  Uncategorized Expense is allowed and a no-op on its `category_id`.
  """
  @spec unassign_category(t(), Expense.id()) ::
          {:ok, t(), Expense.t()} | {:error, :expense_not_found}
  def unassign_category(%__MODULE__{} = document, expense_id) do
    case Enum.any?(document.expenses, &(&1.id == expense_id)) do
      false -> {:error, :expense_not_found}
      true -> set_expense_category(document, expense_id, nil)
    end
  end

  # Sets the `category_id` of the Expense `expense_id` (to a Category id or `nil`),
  # returning the updated document and Expense. The caller has already verified the
  # Expense exists, so `Enum.find_index/2` never returns `nil` here.
  defp set_expense_category(document, expense_id, category_id) do
    index = Enum.find_index(document.expenses, &(&1.id == expense_id))
    expense = %{Enum.at(document.expenses, index) | category_id: category_id}
    {:ok, %{document | expenses: List.replace_at(document.expenses, index, expense)}, expense}
  end

  defp unfile_expenses(expenses, category_id) do
    Enum.map(expenses, fn
      %Expense{category_id: ^category_id} = expense -> %{expense | category_id: nil}
      expense -> expense
    end)
  end

  defp category_from_raw(%{id: id, name: name}), do: %Category{id: id, name: name}

  defp category_to_raw(%Category{id: id, name: name}), do: %{id: id, name: name}

  defp expense_from_raw(%{
         id: id,
         date: date,
         description: description,
         cost: cost,
         category_id: category_id
       }) do
    %Expense{
      id: id,
      date: Date.from_iso8601!(date),
      description: description,
      cost: cost_from_raw(cost),
      category_id: category_id
    }
  end

  defp cost_from_raw(nil), do: nil
  defp cost_from_raw(cost) when is_binary(cost), do: Decimal.new(cost)

  defp expense_to_raw(%Expense{
         id: id,
         date: date,
         description: description,
         cost: cost,
         category_id: category_id
       }) do
    %{
      id: id,
      date: Date.to_iso8601(date),
      description: description,
      cost: cost_to_raw(cost),
      category_id: category_id
    }
  end

  defp cost_to_raw(nil), do: nil
  defp cost_to_raw(%Decimal{} = cost), do: Decimal.to_string(cost, :normal)
end
