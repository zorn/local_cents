defmodule LocalCents.TrackingTest do
  # Async: every test drives an isolated `:tmp_dir` (threaded into the context
  # functions that touch disk) rather than a shared `:books_dir` env, so the
  # module runs concurrently — see docs/research/avoiding-async-false-tests.md.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.Category
  alias LocalCents.Tracking.Expense

  @moduletag :tmp_dir

  describe "create_book/1" do
    test "returns a Book with an id and the given name", %{tmp_dir: dir} do
      assert {:ok, %Book{id: id, name: "Family Expenses"}} =
               Tracking.create_book("Family Expenses", dir)

      assert byte_size(id) > 0
    end

    test "a new book has no expenses", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      assert Tracking.list_expenses(book.id) == []
    end

    test "each created book gets a distinct id", %{tmp_dir: dir} do
      {:ok, a} = Tracking.create_book("A", dir)
      {:ok, b} = Tracking.create_book("B", dir)
      refute a.id == b.id
    end
  end

  describe "a Book's updated_at" do
    # A fixed, sub-second "now" proves the value is truncated to whole seconds (the
    # resolution Automerge records) and that the injected clock is honored.
    @created ~U[2026-06-02 13:34:20.500000Z]
    @edited ~U[2026-06-02 15:10:05.000000Z]

    test "create_book/3 seeds updated_at from now, truncated to the second", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir, @created)
      assert book.updated_at == ~U[2026-06-02 13:34:20Z]
    end

    test "list_books/1 and get_book/2 expose the derived updated_at", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir, @created)

      assert [%Book{updated_at: ~U[2026-06-02 13:34:20Z]}] = Tracking.list_books(dir)
      assert %Book{updated_at: ~U[2026-06-02 13:34:20Z]} = Tracking.get_book(book.id, dir)
    end

    test "adding an expense advances updated_at", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir, @created)

      {:ok, _expense} =
        Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"}, @edited)

      assert %Book{updated_at: ~U[2026-06-02 15:10:05Z]} = Tracking.get_book(book.id, dir)
    end

    test "renaming advances updated_at", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir, @created)

      :ok = Tracking.rename_book(book.id, "Household", dir, @edited)

      assert %Book{updated_at: ~U[2026-06-02 15:10:05Z]} = Tracking.get_book(book.id, dir)
    end

    test "an epoch (0) now yields no updated_at, consistent with a later read", %{tmp_dir: dir} do
      # A `0` unix stamp is "unset" on the read path (the NIF filters `time > 0`), so
      # the created Book must agree — nil, not the Unix epoch — with what list_books/1
      # would report.
      {:ok, book} = Tracking.create_book("Family", dir, ~U[1970-01-01 00:00:00Z])

      assert book.updated_at == nil
      assert %Book{updated_at: nil} = Tracking.get_book(book.id, dir)
    end
  end

  describe "add_expense/2 and list_expenses/1" do
    test "adds an expense from attrs and returns it as an Expense struct", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:ok, %Expense{id: id, date: ~D[2026-06-02], description: "Coffee"}} =
               Tracking.add_expense(book.id, %{
                 date: ~D[2026-06-02],
                 description: "Coffee",
                 cost: "5.00"
               })

      assert byte_size(id) > 0

      assert [%Expense{description: "Coffee", cost: cost}] = Tracking.list_expenses(book.id)
      assert Decimal.equal?(cost, Decimal.new("5.00"))
    end

    test "an absent cost is stored as nil", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      {:ok, _} = Tracking.add_expense(book.id, %{description: "Gift"})

      assert [%Expense{description: "Gift", cost: nil}] = Tracking.list_expenses(book.id)
    end

    test "invalid attrs return a changeset without persisting anything", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:error, %Ecto.Changeset{}} = Tracking.add_expense(book.id, %{cost: "5.00"})
      assert Tracking.list_expenses(book.id) == []
    end

    test "files the new expense under a category_id passed in attrs", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, category} = Tracking.add_category(book.id, %{name: "Food"})

      assert {:ok, %Expense{category_id: cat_id}} =
               Tracking.add_expense(book.id, %{description: "Coffee", category_id: category.id})

      assert cat_id == category.id
    end

    test "an unknown category_id returns :category_not_found without persisting", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:error, :category_not_found} =
               Tracking.add_expense(book.id, %{description: "Coffee", category_id: "no-such-id"})

      assert Tracking.list_expenses(book.id) == []
    end

    test "all added expenses are present", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee"})
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Lunch"})
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Bus"})

      descriptions = Enum.map(Tracking.list_expenses(book.id), & &1.description)
      assert descriptions == ["Coffee", "Lunch", "Bus"]
    end

    test "returns {:error, :not_open} when the book's process is not running" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} = Tracking.add_expense(id, %{description: "Coffee"})
      assert {:error, :not_open} = Tracking.list_expenses(id)
    end

    test "list_expenses/1 returns {:error, :not_open} for a closed book", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      :ok = Tracking.close_book(book.id)

      assert {:error, :not_open} = Tracking.list_expenses(book.id)
    end
  end

  describe "edit_expense/3" do
    test "replaces the fields of an existing expense", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

      assert {:ok, %Expense{id: id, description: "Latte"}} =
               Tracking.edit_expense(book.id, expense.id, %{
                 description: "Latte",
                 cost: "6.50",
                 date: ~D[2026-06-03]
               })

      assert id == expense.id

      assert [%Expense{description: "Latte", cost: cost}] = Tracking.list_expenses(book.id)
      assert Decimal.equal?(cost, Decimal.new("6.50"))
    end

    test "returns {:error, :not_found} for an unknown expense id", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:error, :not_found} =
               Tracking.edit_expense(book.id, "no-such-id", %{description: "X"})
    end

    test "reassigns and unassigns the category through the edit", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, category} = Tracking.add_category(book.id, %{name: "Food"})
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee"})

      assert {:ok, %Expense{category_id: cat_id}} =
               Tracking.edit_expense(book.id, expense.id, %{
                 description: "Coffee",
                 category_id: category.id
               })

      assert cat_id == category.id

      assert {:ok, %Expense{category_id: nil}} =
               Tracking.edit_expense(book.id, expense.id, %{
                 description: "Coffee",
                 category_id: ""
               })
    end

    test "an unknown category_id returns :category_not_found", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee"})

      assert {:error, :category_not_found} =
               Tracking.edit_expense(book.id, expense.id, %{
                 description: "Coffee",
                 category_id: "no-such-id"
               })
    end

    test "returns {:error, :not_open} when the book's process is not running" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} = Tracking.edit_expense(id, "e", %{description: "X"})
    end
  end

  describe "delete_expense/2" do
    test "removes the expense", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee"})

      assert :ok = Tracking.delete_expense(book.id, expense.id)
      assert Tracking.list_expenses(book.id) == []
    end

    test "returns {:error, :not_found} for an unknown expense id", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:error, :not_found} = Tracking.delete_expense(book.id, "no-such-id")
    end

    test "broadcasts the change to subscribers", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee"})
      :ok = Tracking.subscribe(book.id)

      assert :ok = Tracking.delete_expense(book.id, expense.id)

      assert_receive {:book_updated, id}
      assert id == book.id
    end

    test "returns {:error, :not_open} when the book's process is not running" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} = Tracking.delete_expense(id, "e")
    end
  end

  describe "categories: add/list/rename/delete through the context" do
    test "add_category/2 returns a Category and list_categories/1 sees it", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:ok, %Category{id: id, name: "Groceries"}} =
               Tracking.add_category(book.id, %{name: "Groceries"})

      assert byte_size(id) > 0
      assert [%Category{name: "Groceries"}] = Tracking.list_categories(book.id)
    end

    test "a new book has no categories", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      assert Tracking.list_categories(book.id) == []
    end

    test "a blank name returns a changeset without persisting", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert {:error, %Ecto.Changeset{}} = Tracking.add_category(book.id, %{name: "  "})
      assert Tracking.list_categories(book.id) == []
    end

    test "rename_category/3 changes the name", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})

      assert {:ok, %Category{name: "Food"}} =
               Tracking.rename_category(book.id, category.id, %{name: "Food"})

      assert [%Category{name: "Food"}] = Tracking.list_categories(book.id)
    end

    test "delete_category/2 removes it and un-files its expenses", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Milk"})
      {:ok, _} = Tracking.assign_category(book.id, expense.id, category.id)

      assert :ok = Tracking.delete_category(book.id, category.id)
      assert Tracking.list_categories(book.id) == []
      assert [%Expense{category_id: nil}] = Tracking.list_expenses(book.id)
    end

    test "category commands broadcast :categories_updated alongside :book_updated", %{
      tmp_dir: dir
    } do
      {:ok, book} = Tracking.create_book("Family", dir)
      :ok = Tracking.subscribe(book.id)

      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})
      assert_receive {:categories_updated, id}
      assert id == book.id

      {:ok, _} = Tracking.rename_category(book.id, category.id, %{name: "Food"})
      assert_receive {:categories_updated, ^id}

      :ok = Tracking.delete_category(book.id, category.id)
      assert_receive {:categories_updated, ^id}
    end

    test "expense edits do not broadcast :categories_updated", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      :ok = Tracking.subscribe(book.id)

      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee"})

      assert_receive {:book_updated, _id}
      refute_received {:categories_updated, _id}
    end

    test "the category surface returns {:error, :not_open} for a book with no process" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} = Tracking.list_categories(id)
      assert {:error, :not_open} = Tracking.add_category(id, %{name: "X"})
      assert {:error, :not_open} = Tracking.rename_category(id, "c", %{name: "X"})
      assert {:error, :not_open} = Tracking.delete_category(id, "c")
      assert {:error, :not_open} = Tracking.assign_category(id, "e", "c")
      assert {:error, :not_open} = Tracking.unassign_category(id, "e")
    end
  end

  describe "assign_category/3 and unassign_category/2 through the context" do
    test "files an expense under a category and un-files it, surviving a reopen", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Milk"})

      assert {:ok, %Expense{category_id: cat_id}} =
               Tracking.assign_category(book.id, expense.id, category.id)

      assert cat_id == category.id

      # Reopen the book: the category_id is persisted in the document.
      :ok = Tracking.close_book(book.id)
      :ok = Tracking.open_book(book.id, dir)
      assert [%Expense{category_id: ^cat_id}] = Tracking.list_expenses(book.id)

      assert {:ok, %Expense{category_id: nil}} =
               Tracking.unassign_category(book.id, expense.id)

      assert [%Expense{category_id: nil}] = Tracking.list_expenses(book.id)
    end

    test "assigning reports which side is unknown", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Milk"})
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})

      assert {:error, :expense_not_found} =
               Tracking.assign_category(book.id, "no-such-expense", category.id)

      assert {:error, :category_not_found} =
               Tracking.assign_category(book.id, expense.id, "no-such-category")
    end

    test "adding a category advances updated_at", %{tmp_dir: dir} do
      earlier = ~U[2026-06-01 12:00:00Z]
      later = ~U[2026-06-02 12:00:00Z]
      {:ok, book} = Tracking.create_book("Family", dir, earlier)

      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"}, later)

      assert %Book{updated_at: ^later} = Tracking.get_book(book.id, dir)
    end
  end

  describe "rename_book/2" do
    test "changes the name seen by list_books/1", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Old Name", dir)

      :ok = Tracking.rename_book(book.id, "New Name", dir)

      assert [%Book{id: id, name: "New Name"}] = Tracking.list_books(dir)
      assert id == book.id
    end

    test "renames a closed book by writing its file directly, without starting a process", %{
      tmp_dir: dir
    } do
      {:ok, book} = Tracking.create_book("Old Name", dir)
      :ok = Tracking.close_book(book.id)

      assert :ok = Tracking.rename_book(book.id, "New Name", dir)
      # The rename must not have resurrected the book's runtime process.
      refute LocalCents.Tracking.BookServer.alive?(book.id)
      assert %Book{name: "New Name"} = Tracking.get_book(book.id, dir)
    end

    test "renames an open book through its process and broadcasts the change", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Old Name", dir)
      :ok = Tracking.subscribe(book.id)

      assert :ok = Tracking.rename_book(book.id, "New Name", dir)

      assert_receive {:book_updated, id}
      assert id == book.id
      assert %Book{name: "New Name"} = Tracking.get_book(book.id, dir)
    end

    test "returns an error for an id with no book file", %{tmp_dir: dir} do
      assert {:error, :enoent} =
               Tracking.rename_book("11111111-1111-4111-8111-111111111111", "New Name", dir)
    end
  end

  describe "list_books/0" do
    test "is empty before any book is created", %{tmp_dir: dir} do
      assert Tracking.list_books(dir) == []
    end

    test "enumerates every persisted book", %{tmp_dir: dir} do
      {:ok, a} = Tracking.create_book("Family", dir)
      {:ok, b} = Tracking.create_book("Business", dir)

      by_id = Map.new(Tracking.list_books(dir), &{&1.id, &1.name})
      assert by_id == %{a.id => "Family", b.id => "Business"}
    end

    test "skips a file that is not a valid Book document", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      # A readable .lcbook file that is not a valid Automerge/Book document must
      # not blank the whole library.
      File.write!(Path.join(dir, "bad00000-0000-4000-8000-000000000000.lcbook"), "garbage")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert [%Book{id: id, name: "Family"}] = Tracking.list_books(dir)
          assert id == book.id
        end)

      assert log =~ "Skipping unreadable book file"
    end
  end

  describe "get_book/1" do
    test "returns the Book for a known id", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)

      assert %Book{id: id, name: "Family"} = Tracking.get_book(book.id, dir)
      assert id == book.id
    end

    test "returns nil for an unknown id", %{tmp_dir: dir} do
      assert Tracking.get_book("11111111-1111-4111-8111-111111111111", dir) == nil
    end
  end

  describe "open_book/1 and close_book/1" do
    test "reopening a closed book still reads its persisted expenses", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

      :ok = Tracking.close_book(book.id)
      :ok = Tracking.open_book(book.id, dir)

      assert [%Expense{description: "Coffee", cost: cost}] = Tracking.list_expenses(book.id)
      assert Decimal.equal?(cost, Decimal.new("5.00"))
    end

    test "open_book/1 errors for an unknown id", %{tmp_dir: dir} do
      assert {:error, _reason} = Tracking.open_book("does-not-exist", dir)
    end
  end

  describe "delete_book/1" do
    test "removes the book from the library", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      assert [_] = Tracking.list_books(dir)

      assert :ok = Tracking.delete_book(book.id, dir)
      assert Tracking.list_books(dir) == []
    end

    test "broadcasts to subscribers so an open document window can react", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", dir)
      :ok = Tracking.subscribe(book.id)

      assert :ok = Tracking.delete_book(book.id, dir)

      assert_receive {:book_updated, id}
      assert id == book.id
    end
  end
end
