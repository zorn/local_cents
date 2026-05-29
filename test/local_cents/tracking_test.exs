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

  describe "amount integer boundaries" do
    # Rust stores amount as i64. Rustler decodes Elixir integers to i64 when
    # calling into the NIF — values outside i64 range raise ArgumentError.
    # Elixir integers are arbitrary-precision, so the return direction is always safe.

    @i64_max 9_223_372_036_854_775_807
    @i64_min -9_223_372_036_854_775_808

    test "i64::MAX amount round-trips correctly" do
      book = Tracking.new_book()
      book = Tracking.add_expense(book, %Expense{description: "Max", amount: @i64_max})
      assert [%Expense{amount: @i64_max}] = Tracking.list_expenses(book)
    end

    test "i64::MIN amount round-trips correctly" do
      book = Tracking.new_book()
      book = Tracking.add_expense(book, %Expense{description: "Min", amount: @i64_min})
      assert [%Expense{amount: @i64_min}] = Tracking.list_expenses(book)
    end

    test "negative amounts are accepted (no validation yet)" do
      book = Tracking.new_book()
      book = Tracking.add_expense(book, %Expense{description: "Refund", amount: -500})
      assert [%Expense{amount: -500}] = Tracking.list_expenses(book)
    end

    test "amount exceeding i64::MAX raises ArgumentError" do
      book = Tracking.new_book()
      over_max = @i64_max + 1

      assert_raise ArgumentError, fn ->
        Tracking.add_expense(book, %Expense{description: "Over", amount: over_max})
      end
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
