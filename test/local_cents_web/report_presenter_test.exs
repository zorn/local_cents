defmodule LocalCentsWeb.ReportPresenterTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.Report
  alias LocalCentsWeb.ReportPresenter
  alias LocalCentsWeb.ReportPresenter.Cell

  defp expense(date, cost, category_id) do
    %Expense{
      id: Ecto.UUID.generate(),
      date: date,
      description: "x",
      cost: cost && Decimal.new(cost),
      category_id: category_id
    }
  end

  defp build_view_model(categories, expenses) do
    %BookDocument{name: "Test", categories: categories, expenses: expenses}
    |> Report.compute()
    |> ReportPresenter.to_view_model()
  end

  describe "an empty Report" do
    test "is marked empty with no months or rows" do
      view_model = build_view_model([], [])

      assert view_model.empty?
      assert view_model.months == []
      assert view_model.rows == []
    end
  end

  describe "month column labels" do
    test "render as an abbreviated month and two-digit year" do
      view_model =
        build_view_model([], [
          expense(~D[2026-01-10], "1.00", nil),
          expense(~D[2026-03-10], "1.00", nil)
        ])

      assert Enum.map(view_model.months, & &1.label) == ["Jan '26", "Feb '26", "Mar '26"]
    end
  end

  describe "cell rendering rules" do
    test "known spending renders as dollars" do
      view_model = build_view_model([], [expense(~D[2026-01-10], "50.00", nil)])
      [row] = view_model.rows

      assert hd(row.cells) == %Cell{kind: :money, text: "$50.00"}
    end

    test "spending plus unentered renders dollars with a needs-amount count" do
      expenses = [expense(~D[2026-01-10], "50.00", nil), expense(~D[2026-01-11], nil, nil)]
      view_model = build_view_model([], expenses)
      [row] = view_model.rows

      assert hd(row.cells) == %Cell{kind: :money_needs, text: "$50.00", count: 1}
    end

    test "only-unentered renders a bare needs-amount count, never a dollar amount" do
      view_model = build_view_model([], [expense(~D[2026-01-10], nil, nil)])
      [row] = view_model.rows

      assert hd(row.cells) == %Cell{kind: :needs, count: 1}
    end

    test "a genuine zero month renders as a zero cell" do
      # January and March have spending; February is an in-range zero.
      expenses = [expense(~D[2026-01-10], "5.00", nil), expense(~D[2026-03-10], "5.00", nil)]
      view_model = build_view_model([], expenses)
      [row] = view_model.rows

      assert Enum.at(row.cells, 1) == %Cell{kind: :zero}
    end
  end

  describe "rows and totals" do
    test "the Uncategorized row is named and cells align to the month axis" do
      categories = [category("c1", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-02-10], "7.00", nil)
      ]

      view_model = build_view_model(categories, expenses)

      assert Enum.map(view_model.rows, & &1.name) == ["Groceries", "Uncategorized"]
      # Each row carries one cell per month, in month order.
      assert Enum.all?(view_model.rows, &(length(&1.cells) == length(view_model.months)))

      uncategorized = List.last(view_model.rows)
      assert Enum.at(uncategorized.cells, 0) == %Cell{kind: :zero}
      assert Enum.at(uncategorized.cells, 1) == %Cell{kind: :money, text: "$7.00"}
    end

    test "column totals align to the months and the grand total sums them" do
      expenses = [expense(~D[2026-01-10], "10.00", nil), expense(~D[2026-02-10], "20.00", nil)]
      view_model = build_view_model([], expenses)

      assert length(view_model.column_totals) == length(view_model.months)

      assert view_model.column_totals == [
               %Cell{kind: :money, text: "$10.00"},
               %Cell{kind: :money, text: "$20.00"}
             ]

      assert view_model.grand_total == %Cell{kind: :money, text: "$30.00"}
    end
  end

  defp category(id, name), do: %Category{id: id, name: name}
end
