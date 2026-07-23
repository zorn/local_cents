defmodule LocalCents.Tracking.ReportTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense
  alias LocalCents.Tracking.Month
  alias LocalCents.Tracking.Report

  # Builds a BookDocument straight from typed domain structs, bypassing the CRDT
  # codec — `compute/1` is pure and reads only `categories`/`expenses`.
  defp document(categories, expenses) do
    %BookDocument{name: "Test Book", categories: categories, expenses: expenses}
  end

  defp category(id, name), do: %Category{id: id, name: name}

  defp expense(date, cost, category_id) do
    %Expense{
      id: Ecto.UUID.generate(),
      date: date,
      description: "x",
      cost: cost && Decimal.new(cost),
      category_id: category_id
    }
  end

  defp cell(total, count), do: %Report.Cell{total: Decimal.new(total), needs_amount_count: count}

  describe "an empty Book" do
    test "produces a fully-formed empty Report with a zero grand total" do
      report = Report.compute(document([], []))

      assert report.months == []
      assert report.rows == []
      assert report.column_totals == %{}
      assert report.grand_total == cell("0", 0)
    end

    test "categories with no expenses still produce no rows" do
      report = Report.compute(document([category("c1", "Groceries")], []))

      assert report.rows == []
      assert report.months == []
    end
  end

  describe "the Month column axis" do
    test "spans earliest to latest contiguously, filling empty months in the gap" do
      # Jan and Mar have spending; Feb has none but must still appear as a column.
      expenses = [
        expense(~D[2026-01-10], "10.00", nil),
        expense(~D[2026-03-05], "20.00", nil)
      ]

      report = Report.compute(document([], expenses))

      assert report.months == [Month.new(2026, 1), Month.new(2026, 2), Month.new(2026, 3)]
    end

    test "a nil-cost expense still defines the span" do
      # The only March entry has no amount yet; March must still be a column.
      expenses = [
        expense(~D[2026-01-10], "10.00", nil),
        expense(~D[2026-03-05], nil, nil)
      ]

      report = Report.compute(document([], expenses))
      assert List.last(report.months) == Month.new(2026, 3)
    end
  end

  describe "rows" do
    test "one row per Category that has expenses, alphabetical by name, Uncategorized last" do
      categories = [category("c1", "Utilities"), category("c2", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-01-11], "20.00", "c2"),
        expense(~D[2026-01-12], "5.00", nil)
      ]

      report = Report.compute(document(categories, expenses))

      assert Enum.map(report.rows, fn
               %{category: nil} -> :uncategorized
               %{category: c} -> c.name
             end) == ["Groceries", "Utilities", :uncategorized]
    end

    test "a Category with no expenses produces no row" do
      categories = [category("c1", "Groceries"), category("c2", "Unused")]
      expenses = [expense(~D[2026-01-10], "10.00", "c1")]

      report = Report.compute(document(categories, expenses))
      assert Enum.map(report.rows, & &1.category.name) == ["Groceries"]
    end

    test "an expense whose category_id names no current Category buckets as Uncategorized" do
      # A CRDT merge can leave a dangling reference — an expense filed under a
      # Category a peer deleted. The read model must fold it into Uncategorized, not
      # crash on the missing Category.
      categories = [category("c1", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-01-11], "7.00", "deleted-elsewhere")
      ]

      report = Report.compute(document(categories, expenses))

      assert Enum.map(report.rows, fn
               %{category: nil} -> :uncategorized
               %{category: c} -> c.name
             end) == ["Groceries", :uncategorized]

      uncategorized = Enum.find(report.rows, &is_nil(&1.category))
      assert uncategorized.total == cell("7.00", 0)
    end

    test "a Category whose only expenses are nil-cost still gets a zero-dollar row with a count" do
      categories = [category("c1", "Groceries")]
      expenses = [expense(~D[2026-01-10], nil, "c1")]

      report = Report.compute(document(categories, expenses))
      [row] = report.rows

      assert row.category.name == "Groceries"
      assert row.total == cell("0", 1)
    end

    test "a row holds an explicit zero cell for every in-range month with no spending" do
      categories = [category("c1", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-03-05], "20.00", "c1")
      ]

      report = Report.compute(document(categories, expenses))
      [row] = report.rows

      assert row.cells[Month.new(2026, 1)] == cell("10.00", 0)
      assert row.cells[Month.new(2026, 2)] == cell("0", 0)
      assert row.cells[Month.new(2026, 3)] == cell("20.00", 0)
    end
  end

  describe "the Report range" do
    # A reference "now" so the trailing window is deterministic: current month is July.
    @now ~U[2026-07-15 12:00:00Z]

    defp trailing(document, n),
      do: Report.compute(document, range: {:trailing_months, n}, now: @now)

    test ":all (and compute/1) spans the whole Book" do
      expenses = [expense(~D[2026-01-10], "10.00", nil), expense(~D[2026-04-05], "20.00", nil)]
      doc = document([], expenses)

      whole = Month.range(Month.new(2026, 1), Month.new(2026, 4))
      assert Report.compute(doc, range: :all).months == whole
      assert Report.compute(doc).months == whole
    end

    test "a trailing range spans the last N months from now, inclusive of the current month" do
      expenses = [expense(~D[2026-01-10], "10.00", nil), expense(~D[2026-06-05], "20.00", nil)]

      report = trailing(document([], expenses), 3)

      assert report.months == [Month.new(2026, 5), Month.new(2026, 6), Month.new(2026, 7)]
    end

    test "excludes expenses outside the range from rows, cells, and every total" do
      categories = [category("c1", "Groceries")]

      expenses = [
        # January is outside the trailing-3 window (May–Jul) and must not count.
        expense(~D[2026-01-10], "999.00", "c1"),
        expense(~D[2026-06-05], "20.00", "c1")
      ]

      report = trailing(document(categories, expenses), 3)

      assert report.grand_total == cell("20.00", 0)
      [row] = report.rows
      assert row.total == cell("20.00", 0)
      assert row.cells[Month.new(2026, 6)] == cell("20.00", 0)
      refute Map.has_key?(row.cells, Month.new(2026, 1))
    end

    test "clamps the range start up to the Book's earliest expense" do
      # Earliest expense is June; a trailing-12 window would reach back to Aug 2025,
      # but there is no pre-June data to show, so the span starts at June.
      expenses = [expense(~D[2026-06-10], "10.00", nil), expense(~D[2026-07-01], "5.00", nil)]

      report = trailing(document([], expenses), 12)

      assert report.months == [Month.new(2026, 6), Month.new(2026, 7)]
    end

    test "shows trailing empty months for a stale Book" do
      # Latest activity was May; now is July, so June and July are in-range zeros.
      expenses = [expense(~D[2026-05-10], "10.00", nil)]

      report = trailing(document([], expenses), 3)

      assert report.months == [Month.new(2026, 5), Month.new(2026, 6), Month.new(2026, 7)]
      [row] = report.rows
      assert row.cells[Month.new(2026, 7)] == cell("0", 0)
      assert report.column_totals[Month.new(2026, 7)] == cell("0", 0)
    end

    test "a range entirely before the earliest expense yields an empty Report" do
      # All spending is in the future (December); the trailing-3 window (May–Jul) holds none.
      expenses = [expense(~D[2026-12-10], "10.00", nil)]

      report = trailing(document([], expenses), 3)

      assert report.months == []
      assert report.rows == []
      assert report.grand_total == cell("0", 0)
    end
  end

  describe "nil-cost expenses" do
    test "are counted per cell, never summed as zero, alongside known costs" do
      categories = [category("c1", "Groceries")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-01-11], nil, "c1"),
        expense(~D[2026-01-12], nil, "c1")
      ]

      report = Report.compute(document(categories, expenses))
      [row] = report.rows

      assert row.cells[Month.new(2026, 1)] == cell("10.00", 2)
    end
  end

  describe "totals reconcile" do
    test "per-cell → per-row, per-column, and grand totals all agree" do
      categories = [category("c1", "Groceries"), category("c2", "Utilities")]

      expenses = [
        expense(~D[2026-01-10], "10.00", "c1"),
        expense(~D[2026-02-11], "20.00", "c1"),
        expense(~D[2026-01-15], "30.00", "c2"),
        expense(~D[2026-02-20], nil, "c2"),
        expense(~D[2026-01-25], "5.00", nil)
      ]

      report = Report.compute(document(categories, expenses))

      # Each row's total equals the sum of its own cells.
      for row <- report.rows do
        summed = report.months |> Enum.map(&row.cells[&1]) |> sum_cells()
        assert summed == row.total
      end

      # Each column total equals the sum of that month's cells across rows.
      for month <- report.months do
        summed = report.rows |> Enum.map(& &1.cells[month]) |> sum_cells()
        assert equal_cells?(summed, report.column_totals[month])
      end

      # The grand total equals the sum of all row totals and of all column totals.
      grand_from_rows = report.rows |> Enum.map(& &1.total) |> sum_cells()
      grand_from_cols = report.months |> Enum.map(&report.column_totals[&1]) |> sum_cells()

      assert equal_cells?(grand_from_rows, report.grand_total)
      assert equal_cells?(grand_from_cols, report.grand_total)

      # And to the independently known figures: $65.00 across 5 expenses, 1 unpriced.
      assert report.grand_total == cell("65.00", 1)
    end
  end

  defp sum_cells(cells) do
    Enum.reduce(cells, Report.Cell.zero(), fn c, acc ->
      %Report.Cell{
        total: Decimal.add(acc.total, c.total),
        needs_amount_count: acc.needs_amount_count + c.needs_amount_count
      }
    end)
  end

  # Compares two cells by numeric value so `10.00` and `10` reconcile — a summed
  # Decimal can carry a different scale than a directly computed one.
  defp equal_cells?(%Report.Cell{} = a, %Report.Cell{} = b) do
    Decimal.equal?(a.total, b.total) and a.needs_amount_count == b.needs_amount_count
  end
end
