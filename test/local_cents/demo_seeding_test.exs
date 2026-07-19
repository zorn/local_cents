defmodule LocalCents.DemoSeedingTest do
  # Async: seeds each run's Books into its own `:tmp_dir` (injected into
  # create_books and the library reads), so no shared `:books_dir` env is mutated.
  use ExUnit.Case, async: true

  alias LocalCents.DemoSeeding
  alias LocalCents.Tracking

  @moduletag :tmp_dir

  # A fixed reference "now" makes the 12-month window and the "current month"
  # deterministic. 2026-07-17 is a Friday in mid-month, so day-of-month math for
  # seeded expenses stays inside every month's length.
  @now ~U[2026-07-17 12:00:00Z]
  @today ~D[2026-07-17]

  describe "create_books/2" do
    test "creates exactly the two named demo Books", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      names = dir |> Tracking.list_books() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Business Expenses", "Family Expenses"]
    end

    test "leaves no Book runtime process running (each Book is closed)", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      for book <- Tracking.list_books(dir) do
        assert Tracking.list_expenses(book.id) == {:error, :not_open}
      end
    end

    test "the Family Book carries its full category set", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      family = book_named(dir, "Family Expenses")
      :ok = Tracking.open_book(family.id, dir)

      names = family.id |> Tracking.list_categories() |> Enum.map(& &1.name) |> Enum.sort()

      assert names ==
               Enum.sort([
                 "Car Maintenance",
                 "Clothing",
                 "Dining Out",
                 "Entertainment",
                 "Groceries",
                 "Healthcare",
                 "Housing",
                 "Kids",
                 "Pet",
                 "Transportation",
                 "Utilities",
                 "Vacation"
               ])
    end

    test "the Business Book carries its full category set, including client categories", %{
      tmp_dir: dir
    } do
      :ok = DemoSeeding.create_books(@now, dir)

      business = book_named(dir, "Business Expenses")
      :ok = Tracking.open_book(business.id, dir)

      names = business.id |> Tracking.list_categories() |> Enum.map(& &1.name) |> Enum.sort()

      assert names ==
               Enum.sort([
                 "Business Admin",
                 "Client: Acme Corp",
                 "Client: Blue Fox Studio",
                 "Client: Meridian Health",
                 "Coworking Space",
                 "Hardware & Equipment",
                 "Office Supplies",
                 "Software & Subscriptions",
                 "Tax Preparation"
               ])
    end

    test "expenses span the trailing 12 months, ending in the current month", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      family = book_named(dir, "Family Expenses")
      :ok = Tracking.open_book(family.id, dir)

      dates = family.id |> Tracking.list_expenses() |> Enum.map(& &1.date)

      earliest = Enum.min(dates, Date)
      latest = Enum.max(dates, Date)

      # 11 whole months before the current month is the far edge of the window.
      assert {earliest.year, earliest.month} == {2025, 8}
      assert {latest.year, latest.month} == {@today.year, @today.month}
    end

    test "every calendar month in the window is populated (no empty columns)", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      family = book_named(dir, "Family Expenses")
      :ok = Tracking.open_book(family.id, dir)

      months =
        family.id
        |> Tracking.list_expenses()
        |> Enum.map(&{&1.date.year, &1.date.month})
        |> Enum.uniq()

      assert length(months) == 12
    end

    test "recent inbox: uncategorized and nil-cost expenses sit in the current month", %{
      tmp_dir: dir
    } do
      :ok = DemoSeeding.create_books(@now, dir)

      family = book_named(dir, "Family Expenses")
      :ok = Tracking.open_book(family.id, dir)
      expenses = Tracking.list_expenses(family.id)

      uncategorized = Enum.filter(expenses, &is_nil(&1.category_id))
      unpriced = Enum.filter(expenses, &is_nil(&1.cost))

      assert uncategorized != []
      assert unpriced != []

      # The messy stragglers read as freshly captured: all in the current month.
      for expense <- uncategorized ++ unpriced do
        assert {expense.date.year, expense.date.month} == {@today.year, @today.month}
      end
    end

    test "settled history is fully categorized and priced", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(@now, dir)

      family = book_named(dir, "Family Expenses")
      :ok = Tracking.open_book(family.id, dir)

      settled =
        family.id
        |> Tracking.list_expenses()
        |> Enum.reject(&({&1.date.year, &1.date.month} == {@today.year, @today.month}))

      assert settled != []
      assert Enum.all?(settled, &(&1.category_id != nil))
      assert Enum.all?(settled, &(&1.cost != nil))
    end
  end

  defp book_named(dir, name), do: Enum.find(Tracking.list_books(dir), &(&1.name == name))
end
