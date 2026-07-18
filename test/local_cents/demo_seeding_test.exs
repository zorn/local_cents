defmodule LocalCents.DemoSeedingTest do
  # Not async: seeds Books through the global :books_dir env.
  use ExUnit.Case, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.DemoSeeding
  alias LocalCents.Tracking

  setup :with_temp_books_dir

  # A fixed reference "now" makes the 12-month window and the "current month"
  # deterministic. 2026-07-17 is a Friday in mid-month, so day-of-month math for
  # seeded expenses stays inside every month's length.
  @now ~U[2026-07-17 12:00:00Z]
  @today ~D[2026-07-17]

  describe "create_books/1" do
    test "creates exactly the two named demo Books" do
      :ok = DemoSeeding.create_books(@now)

      names = Tracking.list_books() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Business Expenses", "Family Expenses"]
    end

    test "leaves no Book runtime process running (each Book is closed)" do
      :ok = DemoSeeding.create_books(@now)

      for book <- Tracking.list_books() do
        assert Tracking.list_expenses(book.id) == {:error, :not_open}
      end
    end

    test "the Family Book carries its full category set" do
      :ok = DemoSeeding.create_books(@now)

      family = book_named("Family Expenses")
      :ok = Tracking.open_book(family.id)

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

    test "the Business Book carries its full category set, including client categories" do
      :ok = DemoSeeding.create_books(@now)

      business = book_named("Business Expenses")
      :ok = Tracking.open_book(business.id)

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

    test "expenses span the trailing 12 months, ending in the current month" do
      :ok = DemoSeeding.create_books(@now)

      family = book_named("Family Expenses")
      :ok = Tracking.open_book(family.id)

      dates = family.id |> Tracking.list_expenses() |> Enum.map(& &1.date)

      earliest = Enum.min(dates, Date)
      latest = Enum.max(dates, Date)

      # 11 whole months before the current month is the far edge of the window.
      assert {earliest.year, earliest.month} == {2025, 8}
      assert {latest.year, latest.month} == {@today.year, @today.month}
    end

    test "every calendar month in the window is populated (no empty columns)" do
      :ok = DemoSeeding.create_books(@now)

      family = book_named("Family Expenses")
      :ok = Tracking.open_book(family.id)

      months =
        family.id
        |> Tracking.list_expenses()
        |> Enum.map(&{&1.date.year, &1.date.month})
        |> Enum.uniq()

      assert length(months) == 12
    end

    test "recent inbox: uncategorized and nil-cost expenses sit in the current month" do
      :ok = DemoSeeding.create_books(@now)

      family = book_named("Family Expenses")
      :ok = Tracking.open_book(family.id)
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

    test "settled history is fully categorized and priced" do
      :ok = DemoSeeding.create_books(@now)

      family = book_named("Family Expenses")
      :ok = Tracking.open_book(family.id)

      settled =
        family.id
        |> Tracking.list_expenses()
        |> Enum.reject(&({&1.date.year, &1.date.month} == {@today.year, @today.month}))

      assert settled != []
      assert Enum.all?(settled, &(&1.category_id != nil))
      assert Enum.all?(settled, &(&1.cost != nil))
    end
  end

  defp book_named(name), do: Enum.find(Tracking.list_books(), &(&1.name == name))
end
