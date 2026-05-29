defmodule LocalCents.TrackingTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Expense

  describe "new_book/0" do
    test "returns a non-empty binary" do
      book = Tracking.new_book()
      assert is_binary(book)
      assert byte_size(book) > 0
    end

    test "new book has no expenses" do
      book = Tracking.new_book()
      assert Tracking.list_expenses(book) == []
    end
  end

  describe "add_expense/2" do
    test "adds a single expense and returns it as an Expense struct" do
      book = Tracking.new_book()

      book = Tracking.add_expense(book, %Expense{description: "Coffee", amount: 500})

      assert [
               %Expense{description: "Coffee", amount: 500}
             ] = Tracking.list_expenses(book)
    end

    test "all added expenses are present in the book" do
      book = Tracking.new_book()

      book =
        book
        |> Tracking.add_expense(%Expense{description: "Coffee", amount: 500})
        |> Tracking.add_expense(%Expense{description: "Lunch", amount: 1200})
        |> Tracking.add_expense(%Expense{description: "Bus", amount: 250})

      expenses = Tracking.list_expenses(book)
      assert length(expenses) == 3
      assert %Expense{description: "Coffee", amount: 500} in expenses
      assert %Expense{description: "Lunch", amount: 1200} in expenses
      assert %Expense{description: "Bus", amount: 250} in expenses
    end
  end

  describe "merge/2" do
    test "merging two books preserves expenses from both" do
      starting_book = Tracking.new_book()

      starting_book =
        Tracking.add_expense(starting_book, %Expense{description: "Coffee", amount: 500})

      fork_a = Tracking.add_expense(starting_book, %Expense{description: "Lunch", amount: 1200})
      fork_b = Tracking.add_expense(starting_book, %Expense{description: "Bus", amount: 250})

      merged_book = Tracking.merge(fork_a, fork_b)
      descriptions = merged_book |> Tracking.list_expenses() |> Enum.map(& &1.description)

      assert "Coffee" in descriptions
      assert "Lunch" in descriptions
      assert "Bus" in descriptions
      assert length(descriptions) == 3
    end

    test "merge is commutative for the resulting expense set" do
      starting_book = Tracking.new_book()

      fork_a = Tracking.add_expense(starting_book, %Expense{description: "A", amount: 100})
      fork_b = Tracking.add_expense(starting_book, %Expense{description: "B", amount: 200})

      merged_ab = Tracking.merge(fork_a, fork_b)
      merged_ba = Tracking.merge(fork_b, fork_a)

      set_ab = merged_ab |> Tracking.list_expenses() |> MapSet.new()
      set_ba = merged_ba |> Tracking.list_expenses() |> MapSet.new()

      assert set_ab == set_ba
    end
  end
end
