defmodule LocalCents.TrackingTest do
  # Not async: uses a temporary books directory via the global :books_dir env.
  use ExUnit.Case, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.Expense

  setup :with_temp_books_dir

  describe "create_book/1" do
    test "returns a Book with an id and the given name" do
      assert {:ok, %Book{id: id, name: "Family Expenses"}} =
               Tracking.create_book("Family Expenses")

      assert is_binary(id)
    end

    test "a new book has no expenses" do
      {:ok, book} = Tracking.create_book("Family")
      assert Tracking.list_expenses(book.id) == []
    end

    test "each created book gets a distinct id" do
      {:ok, a} = Tracking.create_book("A")
      {:ok, b} = Tracking.create_book("B")
      refute a.id == b.id
    end
  end

  describe "add_expense/2 and list_expenses/1" do
    test "adds an expense and returns it as an Expense struct" do
      {:ok, book} = Tracking.create_book("Family")

      :ok = Tracking.add_expense(book.id, %Expense{description: "Coffee", amount: 500})

      assert [%Expense{description: "Coffee", amount: 500}] = Tracking.list_expenses(book.id)
    end

    test "all added expenses are present" do
      {:ok, book} = Tracking.create_book("Family")

      :ok = Tracking.add_expense(book.id, %Expense{description: "Coffee", amount: 500})
      :ok = Tracking.add_expense(book.id, %Expense{description: "Lunch", amount: 1200})
      :ok = Tracking.add_expense(book.id, %Expense{description: "Bus", amount: 250})

      expenses = Tracking.list_expenses(book.id)
      assert length(expenses) == 3
      assert %Expense{description: "Coffee", amount: 500} in expenses
      assert %Expense{description: "Lunch", amount: 1200} in expenses
      assert %Expense{description: "Bus", amount: 250} in expenses
    end

    test "returns {:error, :not_open} when the book's process is not running" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} =
               Tracking.add_expense(id, %Expense{description: "Coffee", amount: 500})

      assert {:error, :not_open} = Tracking.rename_book(id, "New Name")
      assert {:error, :not_open} = Tracking.list_expenses(id)
    end

    test "list_expenses/1 returns {:error, :not_open} for a closed book" do
      {:ok, book} = Tracking.create_book("Family")
      :ok = Tracking.close_book(book.id)

      assert {:error, :not_open} = Tracking.list_expenses(book.id)
    end
  end

  describe "rename_book/2" do
    test "changes the name seen by list_books/0" do
      {:ok, book} = Tracking.create_book("Old Name")

      :ok = Tracking.rename_book(book.id, "New Name")

      assert [%Book{id: id, name: "New Name"}] = Tracking.list_books()
      assert id == book.id
    end
  end

  describe "list_books/0" do
    test "is empty before any book is created" do
      assert Tracking.list_books() == []
    end

    test "enumerates every persisted book" do
      {:ok, a} = Tracking.create_book("Family")
      {:ok, b} = Tracking.create_book("Business")

      by_id = Map.new(Tracking.list_books(), &{&1.id, &1.name})
      assert by_id == %{a.id => "Family", b.id => "Business"}
    end

    test "skips a file that is not a valid Book document", %{books_dir: dir} do
      {:ok, book} = Tracking.create_book("Family")
      # A readable .lcbook file that is not a valid Automerge/Book document must
      # not blank the whole library.
      File.write!(Path.join(dir, "bad00000-0000-4000-8000-000000000000.lcbook"), "garbage")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert [%Book{id: id, name: "Family"}] = Tracking.list_books()
          assert id == book.id
        end)

      assert log =~ "Skipping unreadable book file"
    end
  end

  describe "get_book/1" do
    test "returns the Book for a known id" do
      {:ok, book} = Tracking.create_book("Family")

      assert %Book{id: id, name: "Family"} = Tracking.get_book(book.id)
      assert id == book.id
    end

    test "returns nil for an unknown id" do
      assert Tracking.get_book("11111111-1111-4111-8111-111111111111") == nil
    end
  end

  describe "open_book/1 and close_book/1" do
    test "reopening a closed book still reads its persisted expenses" do
      {:ok, book} = Tracking.create_book("Family")
      :ok = Tracking.add_expense(book.id, %Expense{description: "Coffee", amount: 500})

      :ok = Tracking.close_book(book.id)
      :ok = Tracking.open_book(book.id)

      assert [%Expense{description: "Coffee", amount: 500}] = Tracking.list_expenses(book.id)
    end

    test "open_book/1 errors for an unknown id" do
      assert {:error, _reason} = Tracking.open_book("does-not-exist")
    end
  end

  describe "delete_book/1" do
    test "removes the book from the library" do
      {:ok, book} = Tracking.create_book("Family")
      assert [_] = Tracking.list_books()

      assert :ok = Tracking.delete_book(book.id)
      assert Tracking.list_books() == []
    end
  end
end
