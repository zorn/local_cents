defmodule LocalCents.TrackingTest do
  use ExUnit.Case

  describe "new_book/0" do
    test "can create a new book" do
      assert false
    end
  end

  describe "add_expense/2" do
    test "can add expenses to a new book" do
    end

    test "fails if not passing in a book" do
    end
  end

  describe "list_expenses/1" do
    test "returns an empty list for a new book" do
    end

    test "returns the expenses that have been added to the book" do
    end

    test "fails if not passing in a book" do
      # Q: Is this too noisy of a test?
    end
  end
end
