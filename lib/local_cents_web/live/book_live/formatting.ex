defmodule LocalCentsWeb.BookLive.Formatting do
  @moduledoc """
  Viewer-zone helpers shared by `LocalCentsWeb.BookLive` and its
  `LocalCentsWeb.BookLive.Editor`: the viewer's local `today`, and the display strings for
  an `Expense`'s date and cost.

  Extracted so the Book view and its editor read these through one module rather than each
  taking a direct dependency on `Decimal`, `Calendar`, and `DateTime` — the collapse that
  keeps `BookLive` inside its module-dependency budget (see
  [#267](https://github.com/zorn/local_cents/issues/267)). Every function here answers "in
  the viewer's own zone, what does this value read as", which is why the local-date resolver
  sits beside the two formatters.
  """

  alias LocalCentsWeb.MoneyFormat

  @doc """
  The viewer's *local* calendar date.

  The domain treats "today" as the user's date, not the server's (see `LocalCents.Tracking`),
  so a blank expense date defaults to the right day near midnight in any zone. Falls back to
  UTC on an unknown zone.
  """
  @spec today(time_zone :: String.t()) :: Date.t()
  def today(time_zone) do
    case DateTime.now(time_zone) do
      {:ok, now} -> DateTime.to_date(now)
      {:error, _reason} -> Date.utc_today()
    end
  end

  @doc "The expense date as `MM/DD/YYYY` for the list."
  @spec format_date(Date.t()) :: String.t()
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%m/%d/%Y")

  @doc """
  The cost as `$X.XX`, or an em dash when absent.

  Cost is optional; a nil cost is an honest "needs amount", shown as an em dash rather than
  a fake $0.00 (see [ADR 0008](0008-mvp-expense-shape.html)). A present amount uses the
  shared house formatter so this list and the Report render dollars identically.
  """
  @spec format_amount(Decimal.t() | nil) :: String.t()
  def format_amount(nil), do: "—"
  def format_amount(%Decimal{} = cost), do: MoneyFormat.dollars(cost)
end
