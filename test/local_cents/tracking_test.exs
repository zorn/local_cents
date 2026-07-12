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

      assert byte_size(id) > 0
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

  describe "a Book's updated_at" do
    # A fixed, sub-second "now" proves the value is truncated to whole seconds (the
    # resolution Automerge records) and that the injected clock is honored.
    @created ~U[2026-06-02 13:34:20.500000Z]
    @edited ~U[2026-06-02 15:10:05.000000Z]

    test "create_book/2 seeds updated_at from now, truncated to the second" do
      {:ok, book} = Tracking.create_book("Family", @created)
      assert book.updated_at == ~U[2026-06-02 13:34:20Z]
    end

    test "list_books/0 and get_book/1 expose the derived updated_at" do
      {:ok, book} = Tracking.create_book("Family", @created)

      assert [%Book{updated_at: ~U[2026-06-02 13:34:20Z]}] = Tracking.list_books()
      assert %Book{updated_at: ~U[2026-06-02 13:34:20Z]} = Tracking.get_book(book.id)
    end

    test "adding an expense advances updated_at" do
      {:ok, book} = Tracking.create_book("Family", @created)

      {:ok, _expense} =
        Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"}, @edited)

      assert %Book{updated_at: ~U[2026-06-02 15:10:05Z]} = Tracking.get_book(book.id)
    end

    test "renaming advances updated_at" do
      {:ok, book} = Tracking.create_book("Family", @created)

      :ok = Tracking.rename_book(book.id, "Household", @edited)

      assert %Book{updated_at: ~U[2026-06-02 15:10:05Z]} = Tracking.get_book(book.id)
    end

    test "an epoch (0) now yields no updated_at, consistent with a later read" do
      # A `0` unix stamp is "unset" on the read path (the NIF filters `time > 0`), so
      # the created Book must agree — nil, not the Unix epoch — with what list_books/0
      # would report.
      {:ok, book} = Tracking.create_book("Family", ~U[1970-01-01 00:00:00Z])

      assert book.updated_at == nil
      assert %Book{updated_at: nil} = Tracking.get_book(book.id)
    end
  end

  describe "add_expense/2 and list_expenses/1" do
    test "adds an expense from attrs and returns it as an Expense struct" do
      {:ok, book} = Tracking.create_book("Family")

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

    test "an absent cost is stored as nil" do
      {:ok, book} = Tracking.create_book("Family")

      {:ok, _} = Tracking.add_expense(book.id, %{description: "Gift"})

      assert [%Expense{description: "Gift", cost: nil}] = Tracking.list_expenses(book.id)
    end

    test "invalid attrs return a changeset without persisting anything" do
      {:ok, book} = Tracking.create_book("Family")

      assert {:error, %Ecto.Changeset{}} = Tracking.add_expense(book.id, %{cost: "5.00"})
      assert Tracking.list_expenses(book.id) == []
    end

    test "all added expenses are present" do
      {:ok, book} = Tracking.create_book("Family")

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

    test "list_expenses/1 returns {:error, :not_open} for a closed book" do
      {:ok, book} = Tracking.create_book("Family")
      :ok = Tracking.close_book(book.id)

      assert {:error, :not_open} = Tracking.list_expenses(book.id)
    end
  end

  describe "edit_expense/3" do
    test "replaces the fields of an existing expense" do
      {:ok, book} = Tracking.create_book("Family")
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

    test "returns {:error, :not_found} for an unknown expense id" do
      {:ok, book} = Tracking.create_book("Family")

      assert {:error, :not_found} =
               Tracking.edit_expense(book.id, "no-such-id", %{description: "X"})
    end

    test "returns {:error, :not_open} when the book's process is not running" do
      id = "11111111-1111-4111-8111-111111111111"

      assert {:error, :not_open} = Tracking.edit_expense(id, "e", %{description: "X"})
    end
  end

  describe "delete_expense/2" do
    test "removes the expense" do
      {:ok, book} = Tracking.create_book("Family")
      {:ok, expense} = Tracking.add_expense(book.id, %{description: "Coffee"})

      assert :ok = Tracking.delete_expense(book.id, expense.id)
      assert Tracking.list_expenses(book.id) == []
    end

    test "returns {:error, :not_found} for an unknown expense id" do
      {:ok, book} = Tracking.create_book("Family")

      assert {:error, :not_found} = Tracking.delete_expense(book.id, "no-such-id")
    end

    test "broadcasts the change to subscribers" do
      {:ok, book} = Tracking.create_book("Family")
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

  describe "rename_book/2" do
    test "changes the name seen by list_books/0" do
      {:ok, book} = Tracking.create_book("Old Name")

      :ok = Tracking.rename_book(book.id, "New Name")

      assert [%Book{id: id, name: "New Name"}] = Tracking.list_books()
      assert id == book.id
    end

    test "renames a closed book by writing its file directly, without starting a process" do
      {:ok, book} = Tracking.create_book("Old Name")
      :ok = Tracking.close_book(book.id)

      assert :ok = Tracking.rename_book(book.id, "New Name")
      # The rename must not have resurrected the book's runtime process.
      refute LocalCents.Tracking.BookServer.alive?(book.id)
      assert %Book{name: "New Name"} = Tracking.get_book(book.id)
    end

    test "renames an open book through its process and broadcasts the change" do
      {:ok, book} = Tracking.create_book("Old Name")
      :ok = Tracking.subscribe(book.id)

      assert :ok = Tracking.rename_book(book.id, "New Name")

      assert_receive {:book_updated, id}
      assert id == book.id
      assert %Book{name: "New Name"} = Tracking.get_book(book.id)
    end

    test "returns an error for an id with no book file" do
      assert {:error, :enoent} =
               Tracking.rename_book("11111111-1111-4111-8111-111111111111", "New Name")
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
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

      :ok = Tracking.close_book(book.id)
      :ok = Tracking.open_book(book.id)

      assert [%Expense{description: "Coffee", cost: cost}] = Tracking.list_expenses(book.id)
      assert Decimal.equal?(cost, Decimal.new("5.00"))
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

    test "broadcasts to subscribers so an open document window can react" do
      {:ok, book} = Tracking.create_book("Family")
      :ok = Tracking.subscribe(book.id)

      assert :ok = Tracking.delete_book(book.id)

      assert_receive {:book_updated, id}
      assert id == book.id
    end
  end
end
