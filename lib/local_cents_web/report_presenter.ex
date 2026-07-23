defmodule LocalCentsWeb.ReportPresenter do
  @moduledoc """
  Maps a `LocalCents.Tracking.Report` into a flat, fully-formatted view model for
  `LocalCentsWeb.Bond.Composites.ReportMatrix`.

  The matrix component stays domain-agnostic — it renders strings and tagged cell
  shapes, never a `Decimal`, a `Month`, or a `Category` (mirroring how
  `ExpenseCell` takes an `amount_display` string). This module is the seam that does
  the formatting: month labels, the per-cell rendering rules, and aligning each row's
  cells and the column totals to the shared month axis.

  ## Cell kinds

  Each cell (and every total, which reuses the same shape) is tagged so the template
  can pattern-match without re-deriving anything (see
  [ADR 0021](0021-bounded-report-range.html) /
  [ADR 0008](0008-mvp-expense-shape.html)):

    * `%{kind: :money, text: "$50.00"}` — known spending, nothing unentered.
    * `%{kind: :money_needs, text: "$50.00", count: n}` — known spending plus `n`
      Expenses whose amount is not entered yet.
    * `%{kind: :needs, count: n}` — only unentered Expenses; never shown as `$0`.
    * `%{kind: :zero}` — a genuine zero: no spending and nothing pending.
  """

  alias LocalCents.Tracking.Month
  alias LocalCents.Tracking.Report
  alias LocalCents.Tracking.Report.Cell
  alias LocalCentsWeb.MoneyFormat

  @month_abbrev {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
                 "Dec"}

  @type cell_vm() ::
          %{kind: :money, text: String.t()}
          | %{kind: :money_needs, text: String.t(), count: pos_integer()}
          | %{kind: :needs, count: pos_integer()}
          | %{kind: :zero}

  @type t() :: %{
          empty?: boolean(),
          months: [%{label: String.t()}],
          rows: [%{name: String.t(), cells: [cell_vm()], total: cell_vm()}],
          column_totals: [cell_vm()],
          grand_total: cell_vm()
        }

  @doc """
  Builds the view model for `report`.
  """
  @spec to_view_model(Report.t()) :: t()
  def to_view_model(%Report{} = report) do
    %{
      empty?: report.months == [],
      months: Enum.map(report.months, &%{label: month_label(&1)}),
      rows: Enum.map(report.rows, &row_vm(&1, report.months)),
      column_totals: Enum.map(report.months, &cell_vm(report.column_totals[&1])),
      grand_total: cell_vm(report.grand_total)
    }
  end

  defp row_vm(row, months) do
    %{
      name: category_name(row.category),
      cells: Enum.map(months, &cell_vm(row.cells[&1])),
      total: cell_vm(row.total)
    }
  end

  defp cell_vm(%Cell{total: total, needs_amount_count: needs}) do
    money? = Decimal.gt?(total, 0)

    cond do
      money? and needs > 0 ->
        %{kind: :money_needs, text: MoneyFormat.dollars(total), count: needs}

      money? ->
        %{kind: :money, text: MoneyFormat.dollars(total)}

      needs > 0 ->
        %{kind: :needs, count: needs}

      true ->
        %{kind: :zero}
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
