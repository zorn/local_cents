defmodule LocalCents.Tracking.Report do
  @moduledoc """
  A computed, read-only summary of a Book's `Expense`s: a Category × Month matrix of
  spending totals (see [ADR 0020](0020-bounded-time-series-in-review.html)).

  `compute/1` folds a `LocalCents.Tracking.BookDocument` into this shape and stores
  nothing of its own — a Report is recomputed on demand, never persisted. The
  `Category` rows are the axis of "what kind of spending," the `LocalCents.Tracking.Month`
  columns are the axis of "when," and each `Cell` holds the money spent there.

  The layout is row-oriented, mirroring how the matrix reads and renders:

    * `months` — the ordered column axis, contiguous from the earliest to the latest
      populated Month (see `LocalCents.Tracking.Month.range/2`). A Month with no
      spending still appears, as an explicit zero cell — absence is signal.
    * `rows` — one `Row` per Category that has any Expense, sorted alphabetically by
      name (ties broken by the Category's stable `id`), with the **Uncategorized**
      row (`category: nil`) pinned last. A Category with no Expenses produces no row.
    * `column_totals` — the per-Month grand across all rows, keyed by `Month`.
    * `grand_total` — the bottom-right cell: every Expense summed.

  ## Known cost vs. needs-amount

  Every `Cell` (and every row/column/grand total, which reuse the same shape) carries
  two independent values that are **never** conflated: `total`, the sum of *known*
  costs as a `Decimal`, and `needs_amount_count`, how many Expenses in that bucket
  have a `nil` cost. A `nil` cost is real, tracked spending whose amount has not been
  entered yet — it is counted, never summed as `0` (see
  [ADR 0008](0008-mvp-expense-shape.html) / [ADR 0010](0010-cost-as-decimal-string.html)).

  Because a `nil`-cost Expense still has a required `date`, it counts everywhere it
  belongs: it can extend the Month span and it gives its Category a row even when that
  row's known-cost total is `0`.
  """

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.Month

  defmodule Cell do
    @moduledoc """
    One bucket of a `LocalCents.Tracking.Report`: the summed *known* cost plus the
    count of `nil`-cost (needs-amount) Expenses in it.

    The same shape serves an individual Category/Month cell and every aggregate
    total (per-row, per-column, grand), so the "dollars and needs-amount counts are
    distinct" rule holds uniformly and reconciliation checks stay simple. A `nil`
    cost is tallied in `needs_amount_count`, never folded into `total` as `0`.
    """

    @enforce_keys [:total, :needs_amount_count]
    defstruct [:total, :needs_amount_count]

    @type t() :: %__MODULE__{total: Decimal.t(), needs_amount_count: non_neg_integer()}

    @doc """
    The empty bucket: a zero known-cost total and no needs-amount Expenses — the
    identity every sum in a `LocalCents.Tracking.Report` starts from.
    """
    @spec zero() :: t()
    def zero, do: %__MODULE__{total: Decimal.new(0), needs_amount_count: 0}
  end

  defmodule Row do
    @moduledoc """
    One Category's row in a `LocalCents.Tracking.Report`: its per-Month `Cell`s plus
    its lifetime `total`.

    `category` is the full `LocalCents.Tracking.Category` struct, or `nil` for the
    **Uncategorized** row (the computed bucket of Expenses filed under no Category).
    `cells` is keyed by `LocalCents.Tracking.Month` and holds an entry for *every*
    Month in the Report's span — an in-range Month with no spending is an explicit
    zero cell, not a missing key. `total` is the row's lifetime sum (the flat
    per-Category total, which is a strict subset of this matrix).
    """

    alias LocalCents.Tracking.Category
    alias LocalCents.Tracking.Month
    alias LocalCents.Tracking.Report.Cell

    @enforce_keys [:category, :cells, :total]
    defstruct [:category, :cells, :total]

    @type t() :: %__MODULE__{
            category: Category.t() | nil,
            cells: %{Month.t() => Cell.t()},
            total: Cell.t()
          }
  end

  @enforce_keys [:months, :rows, :column_totals, :grand_total]
  defstruct [:months, :rows, :column_totals, :grand_total]

  @type t() :: %__MODULE__{
          months: [Month.t()],
          rows: [Row.t()],
          column_totals: %{Month.t() => Cell.t()},
          grand_total: Cell.t()
        }

  # The row-key for Uncategorized Expenses (those with a `nil` category_id). A plain
  # atom can't collide with a Category id (a UUID string), so it groups cleanly.
  @uncategorized :uncategorized

  @doc """
  Computes the `Report` for `document` — a pure fold over its categories and
  expenses, deriving the whole matrix and every total. Stores nothing; recompute on
  demand.
  """
  @spec compute(BookDocument.t()) :: t()
  def compute(%BookDocument{categories: categories, expenses: expenses}) do
    months = month_span(expenses)
    categories_by_id = Map.new(categories, &{&1.id, &1})
    grouped = Enum.group_by(expenses, &row_key/1)

    rows =
      grouped
      |> Enum.map(fn {key, row_expenses} ->
        build_row(key, row_expenses, months, categories_by_id)
      end)
      |> sort_rows()

    %__MODULE__{
      months: months,
      rows: rows,
      column_totals: column_totals(months, rows),
      grand_total: cell_for(expenses)
    }
  end

  # The contiguous column axis: earliest → latest Month any Expense falls in, gaps
  # filled. Empty when the Book has no Expenses at all.
  defp month_span([]), do: []

  defp month_span(expenses) do
    # `Month` owns chronological ordering, so hand it the comparator rather than
    # re-deriving a year/month key here.
    {earliest, latest} =
      expenses
      |> Enum.map(&Month.from_date(&1.date))
      |> Enum.min_max_by(& &1, Month)

    Month.range(earliest, latest)
  end

  # An Expense's row: its Category's stable id, or the Uncategorized marker.
  defp row_key(%Expense{category_id: nil}), do: @uncategorized
  defp row_key(%Expense{category_id: id}), do: id

  # A row carries a Cell for every Month in the span (explicit zeros included), its
  # Category (or nil for Uncategorized), and its lifetime total.
  defp build_row(key, row_expenses, months, categories_by_id) do
    by_month = Enum.group_by(row_expenses, &Month.from_date(&1.date))
    cells = Map.new(months, fn month -> {month, cell_for(Map.get(by_month, month, []))} end)

    %Row{
      category: category_for(key, categories_by_id),
      cells: cells,
      total: cell_for(row_expenses)
    }
  end

  defp category_for(@uncategorized, _categories_by_id), do: nil
  defp category_for(id, categories_by_id), do: Map.fetch!(categories_by_id, id)

  # Sums a list of Expenses into a Cell: known costs added, nil costs counted.
  defp cell_for(expenses) do
    Enum.reduce(expenses, Cell.zero(), fn
      %Expense{cost: nil}, cell ->
        %{cell | needs_amount_count: cell.needs_amount_count + 1}

      %Expense{cost: %Decimal{} = cost}, cell ->
        %{cell | total: Decimal.add(cell.total, cost)}
    end)
  end

  # Per-Month grand across every row, keyed by Month. Sums the rows' own cells so the
  # column totals reconcile with the cells above them by construction.
  defp column_totals(months, rows) do
    Map.new(months, fn month ->
      cell =
        Enum.reduce(rows, Cell.zero(), fn row, acc ->
          add_cells(acc, Map.fetch!(row.cells, month))
        end)

      {month, cell}
    end)
  end

  defp add_cells(%Cell{} = a, %Cell{} = b) do
    %Cell{
      total: Decimal.add(a.total, b.total),
      needs_amount_count: a.needs_amount_count + b.needs_amount_count
    }
  end

  # Alphabetical by Category name (case-insensitive), ties broken by stable id for a
  # total order; the Uncategorized row (nil category) always sorts last.
  defp sort_rows(rows) do
    Enum.sort_by(rows, fn
      %Row{category: nil} -> {1, "", ""}
      %Row{category: %Category{name: name, id: id}} -> {0, String.downcase(name), id}
    end)
  end
end
