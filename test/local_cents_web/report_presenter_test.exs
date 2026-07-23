defmodule LocalCentsWeb.ReportPresenterTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.Report
  alias LocalCentsWeb.ReportPresenter

  defp expense(date, cost, category_id) do
    %Expense{
      id: Ecto.UUID.generate(),
      date: date,
      description: "x",
      cost: cost && Decimal.new(cost),
      category_id: category_id
    }
  end

  defp view_model(categories, expenses) do
    %BookDocument{name: "Test", categories: categories, expenses: expenses}
    |> Report.compute()
    |> ReportPresenter.to_view_model()
  end

  describe "an empty Report" do
    test "is marked empty with no months or rows" do
      vm = view_model([], [])

      assert vm.empty?
      assert vm.months == []
      assert vm.rows == []
    end
  end

  describe "month column labels" do
    test "render as an abbreviated month and two-digit year" do
      vm =
        view_model([], [
          expense(~D[2026-01-10], "1.00", nil),
          expense(~D[2026-03-10], "1.00", nil)
        ])

      assert Enum.map(vm.months, & &1.label) == ["Jan '26", "Feb '26", "Mar '26"]
    end
  end

  describe "cell rendering rules" do
    test "known spending renders as dollars" do
      vm = view_model([], [expense(~D[2026-01-10], "50.00", nil)])
      [row] = vm.rows

      assert hd(row.cells) == %{kind: :money, text: "$50.00"}
    end

    test "spending plus unentered renders dollars with a needs-amount count" do
      expenses = [expense(~D[2026-01-10], "50.00", nil), expense(~D[2026-01-11], nil, nil)]
      vm = view_model([], expenses)
      [row] = vm.rows

      assert hd(row.cells) == %{kind: :money_needs, text: "$50.00", count: 1}
    end

    test "only-unentered renders a bare needs-amount count, never a dollar amount" do
      vm = view_model([], [expense(~D[2026-01-10], nil, nil)])
      [row] = vm.rows

      assert hd(row.cells) == %{kind: :needs, count: 1}
    end

    test "a genuine zero month renders as a zero cell" do
      # January and March have spending; February is an in-range zero.
      expenses = [expense(~D[2026-01-10], "5.00", nil), expense(~D[2026-03-10], "5.00", nil)]
      vm = view_model([], expenses)
      [row] = vm.rows

      assert Enum.at(row.cells, 1) == %{kind: :zero}
    end
  end

  describe "rows and totals" do
    test "the Uncategorized row is named and cells align to the month axis" do
      categories = [category("c1", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-02-10], "7.00", nil)
      ]

      vm = view_model(categories, expenses)

      assert Enum.map(vm.rows, & &1.name) == ["Groceries", "Uncategorized"]
      # Each row carries one cell per month, in month order.
      assert Enum.all?(vm.rows, &(length(&1.cells) == length(vm.months)))

      uncategorized = List.last(vm.rows)
      assert Enum.at(uncategorized.cells, 0) == %{kind: :zero}
      assert Enum.at(uncategorized.cells, 1) == %{kind: :money, text: "$7.00"}
    end

    test "column totals align to the months and the grand total sums them" do
      expenses = [expense(~D[2026-01-10], "10.00", nil), expense(~D[2026-02-10], "20.00", nil)]
      vm = view_model([], expenses)

      assert length(vm.column_totals) == length(vm.months)

      assert vm.column_totals == [
               %{kind: :money, text: "$10.00"},
               %{kind: :money, text: "$20.00"}
             ]

      assert vm.grand_total == %{kind: :money, text: "$30.00"}
    end
  end

  defp category(id, name), do: %Category{id: id, name: name}
end
