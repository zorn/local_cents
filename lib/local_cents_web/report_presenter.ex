defmodule LocalCentsWeb.ReportPresenter do
  @moduledoc """
  Maps a `LocalCents.Tracking.Report` into a flat, fully-formatted `ViewModel` for
  `LocalCentsWeb.Bond.Composites.ReportMatrix`.

  The matrix component stays domain-agnostic — it renders strings and tagged `Cell`s,
  never a `Decimal`, a `Month`, or a `Category` (mirroring how `ExpenseCell` takes an
  `amount_display` string). This module is the seam that does the formatting: month
  labels, the per-cell rendering rules, and aligning each row's cells and the column
  totals to the shared month axis.

  The output is a tree of small structs (`ViewModel`, `Column`, `Row`, `Cell`) rather
  than bare maps, so the component's `attr`s name a concrete type and a mistyped key
  fails loudly at construction instead of silently rendering blank.

  ## Cell kinds

  Every `Cell` (and every total, which reuses the shape) carries a `kind` tag so the
  template can pattern-match without re-deriving anything (see
  [ADR 0021](0021-bounded-report-range.html) /
  [ADR 0008](0008-mvp-expense-shape.html)). The kind fixes which of `text`/`count`
  are set:

    * `:money` — known spending, nothing unentered. `text` set (e.g. `"$50.00"`).
    * `:money_needs` — known spending plus `count` Expenses whose amount is not entered
      yet. Both `text` and `count` set.
    * `:needs` — only unentered Expenses; `count` set, and never shown as `$0`.
    * `:zero` — a genuine zero: no spending and nothing pending. Neither set.
  """

  alias LocalCents.Tracking.Month
  alias LocalCents.Tracking.Report
  alias LocalCents.Tracking.Report.Cell, as: ReportCell

  alias LocalCentsWeb.MoneyFormat
  alias LocalCentsWeb.ReportPresenter.Cell
  alias LocalCentsWeb.ReportPresenter.Column
  alias LocalCentsWeb.ReportPresenter.Row
  alias LocalCentsWeb.ReportPresenter.ViewModel

  defmodule Cell do
    @moduledoc """
    One fully-formatted matrix cell — the value the template draws without any further
    derivation. The same shape serves an individual Category/Month cell and every
    aggregate total (per-row, per-column, grand).

    `kind` tags the shape (see the `LocalCentsWeb.ReportPresenter` moduledoc); `text`
    holds the rendered `$X.XX` when there is known spending, and `count` the number of
    not-yet-entered amounts when there are any. Each is `nil` for a kind that does not
    use it.
    """

    @enforce_keys [:kind]
    defstruct [:kind, :text, :count]

    @type kind() :: :money | :money_needs | :needs | :zero

    @type t() :: %__MODULE__{
            kind: kind(),
            text: String.t() | nil,
            count: pos_integer() | nil
          }
  end

  defmodule Column do
    @moduledoc """
    One Month column header of the formatted matrix: its display `label` (e.g.
    `Jan '26`). The domain `LocalCents.Tracking.Month` never reaches the component.
    """

    @enforce_keys [:label]
    defstruct [:label]

    @type t() :: %__MODULE__{label: String.t()}
  end

  defmodule Row do
    @moduledoc """
    One Category row of the formatted matrix: its display `name`, one `Cell` per Month
    column in axis order, and its range `total` cell.
    """

    alias LocalCentsWeb.ReportPresenter.Cell

    @enforce_keys [:name, :cells, :total]
    defstruct [:name, :cells, :total]

    @type t() :: %__MODULE__{name: String.t(), cells: [Cell.t()], total: Cell.t()}
  end

  defmodule ViewModel do
    @moduledoc """
    The fully-formatted Report the matrix renders: month `Column`s, Category `Row`s, the
    per-column totals, and the grand total — all as strings and tagged `Cell`s. Built by
    `LocalCentsWeb.ReportPresenter.to_view_model/1`; `empty?` is `true` when the selected
    range has no columns at all.
    """

    alias LocalCentsWeb.ReportPresenter.Cell
    alias LocalCentsWeb.ReportPresenter.Column
    alias LocalCentsWeb.ReportPresenter.Row

    @enforce_keys [:empty?, :months, :rows, :column_totals, :grand_total]
    defstruct [:empty?, :months, :rows, :column_totals, :grand_total]

    @type t() :: %__MODULE__{
            empty?: boolean(),
            months: [Column.t()],
            rows: [Row.t()],
            column_totals: [Cell.t()],
            grand_total: Cell.t()
          }
  end

  @month_abbrev {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
                 "Dec"}

  @doc """
  Builds the `ViewModel` for `report`.
  """
  @spec to_view_model(Report.t()) :: ViewModel.t()
  def to_view_model(%Report{} = report) do
    %ViewModel{
      empty?: report.months == [],
      months: Enum.map(report.months, &%Column{label: month_label(&1)}),
      rows: Enum.map(report.rows, &row_view_model(&1, report.months)),
      column_totals: Enum.map(report.months, &cell_view_model(report.column_totals[&1])),
      grand_total: cell_view_model(report.grand_total)
    }
  end

  defp row_view_model(row, months) do
    %Row{
      name: category_name(row.category),
      cells: Enum.map(months, &cell_view_model(row.cells[&1])),
      total: cell_view_model(row.total)
    }
  end

  defp cell_view_model(%ReportCell{total: total, needs_amount_count: needs}) do
    money? = Decimal.gt?(total, 0)

    cond do
      money? and needs > 0 ->
        %Cell{kind: :money_needs, text: MoneyFormat.dollars(total), count: needs}

      money? ->
        %Cell{kind: :money, text: MoneyFormat.dollars(total)}

      needs > 0 ->
        %Cell{kind: :needs, count: needs}

      true ->
        %Cell{kind: :zero}
    end
  end

  defp category_name(nil), do: "Uncategorized"
  defp category_name(%{name: name}), do: name

  defp month_label(%Month{year: year, month: month}) do
    "#{elem(@month_abbrev, month - 1)} '#{two_digit_year(year)}"
  end

  defp two_digit_year(year),
    do: year |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
end
