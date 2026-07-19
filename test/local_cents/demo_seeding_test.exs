defmodule LocalCents.DemoSeedingTest do
  # Async across modules. Seeding the full demo library costs ~2s, so the read-only
  # assertions share a single `setup_all` seed (into a temp dir this module owns)
  # rather than re-seeding per test. The one test that observes the *just-seeded*
  # runtime state (Books closed) keeps its own fresh seed in an isolated `:tmp_dir`.
  use ExUnit.Case, async: true

  alias LocalCents.DemoSeeding
  alias LocalCents.Tracking

  # A fixed reference "now" makes the 12-month window and the "current month"
  # deterministic. 2026-07-17 is a Friday in mid-month, so day-of-month math for
  # seeded expenses stays inside every month's length.
  @now ~U[2026-07-17 12:00:00Z]
  @today ~D[2026-07-17]

  # Seed the demo library once for all the read-only assertions below. Both Books are
  # opened so tests can list their categories and expenses; everything is torn down
  # (Books closed, temp dir removed) after the last test. The "closes each Book" test
  # ignores this shared context and seeds its own isolated library.
  setup_all do
    dir = Path.join(System.tmp_dir!(), "demo_seeding_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    :ok = DemoSeeding.create_books(now: @now, books_dir: dir)

    family = book_named(dir, "Family Expenses")
    business = book_named(dir, "Business Expenses")
    :ok = Tracking.open_book(family.id, books_dir: dir)
    :ok = Tracking.open_book(business.id, books_dir: dir)

    on_exit(fn ->
      Tracking.close_book(family.id)
      Tracking.close_book(business.id)
      File.rm_rf!(dir)
    end)

    %{dir: dir, family: family, business: business}
  end

  describe "create_books/1" do
    test "creates exactly the two named demo Books", %{dir: dir} do
      names =
        [books_dir: dir]
        |> Tracking.list_books()
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["Business Expenses", "Family Expenses"]
    end

    test "the Family Book carries its full category set", %{family: family} do
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

    test "the Business Book's category set includes client categories", %{business: business} do
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

    test "expenses span the trailing 12 months, ending in the current month", %{family: family} do
      dates = family.id |> Tracking.list_expenses() |> Enum.map(& &1.date)

      earliest = Enum.min(dates, Date)
      latest = Enum.max(dates, Date)

      # 11 whole months before the current month is the far edge of the window.
      assert {earliest.year, earliest.month} == {2025, 8}
      assert {latest.year, latest.month} == {@today.year, @today.month}
    end

    test "every calendar month in the window is populated (no empty columns)", %{family: family} do
      months =
        family.id
        |> Tracking.list_expenses()
        |> Enum.map(&{&1.date.year, &1.date.month})
        |> Enum.uniq()

      assert length(months) == 12
    end

    test "recent inbox: uncategorized and nil-cost expenses sit in the current month", %{
      family: family
    } do
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

    test "settled history is fully categorized and priced", %{family: family} do
      settled =
        family.id
        |> Tracking.list_expenses()
        |> Enum.reject(&({&1.date.year, &1.date.month} == {@today.year, @today.month}))

      assert settled != []
      assert Enum.all?(settled, &(&1.category_id != nil))
      assert Enum.all?(settled, &(&1.cost != nil))
    end
  end

  describe "create_books/1 closes each Book" do
    # This assertion observes the runtime state seeding *leaves behind*, so it needs a
    # fresh seed no other test has opened — its own isolated library.
    @tag :tmp_dir
    test "leaves no Book runtime process running", %{tmp_dir: dir} do
      :ok = DemoSeeding.create_books(now: @now, books_dir: dir)

      for book <- Tracking.list_books(books_dir: dir) do
        assert Tracking.list_expenses(book.id) == {:error, :not_open}
      end
    end
  end

  defp book_named(dir, name),
    do: Enum.find(Tracking.list_books(books_dir: dir), &(&1.name == name))
end
