defmodule LocalCents.Tracking.ExAutomergeTest do
  # Exercises the Rust NIF boundary directly: document creation, the Book name that
  # lives inside the document, expense round-tripping, i64 amount limits, the
  # change-time "last updated" derivation, and CRDT merge. Higher-level behavior is
  # covered through `LocalCents.Tracking`.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.ExAutomerge

  # Fixed unix-seconds stamps for deterministic change times. `@t2` is later than
  # `@t1` so tests can assert the "most recent" behavior.
  @t1 1_700_000_000
  @t2 1_700_000_500

  describe "new_document/2 and document_name/1" do
    test "a new document carries its name and has no expenses" do
      doc = ExAutomerge.new_document("Family Expenses", @t1)
      assert byte_size(doc) > 0
      assert ExAutomerge.document_name(doc) == "Family Expenses"
      assert ExAutomerge.list_expenses(doc) == []
    end
  end

  describe "rename/3" do
    test "updates the name and preserves expenses" do
      doc =
        "Old Name"
        |> ExAutomerge.new_document(@t1)
        |> ExAutomerge.add_expense("Coffee", 500, @t1)
        |> ExAutomerge.rename("New Name", @t2)

      assert ExAutomerge.document_name(doc) == "New Name"
      assert [%{description: "Coffee", amount: 500}] = ExAutomerge.list_expenses(doc)
    end
  end

  describe "add_expense/4 and list_expenses/1" do
    test "all added expenses are present" do
      doc =
        "Book"
        |> ExAutomerge.new_document(@t1)
        |> ExAutomerge.add_expense("Coffee", 500, @t1)
        |> ExAutomerge.add_expense("Lunch", 1200, @t1)
        |> ExAutomerge.add_expense("Bus", 250, @t1)

      expenses = ExAutomerge.list_expenses(doc)
      assert length(expenses) == 3
      assert %{description: "Coffee", amount: 500} in expenses
      assert %{description: "Lunch", amount: 1200} in expenses
      assert %{description: "Bus", amount: 250} in expenses
    end
  end

  describe "document_updated_at/1" do
    test "a new document reports the time it was created with" do
      doc = ExAutomerge.new_document("Book", @t1)
      assert ExAutomerge.document_updated_at(doc) == @t1
    end

    test "reports the time of the most recent change" do
      doc =
        "Book"
        |> ExAutomerge.new_document(@t1)
        |> ExAutomerge.add_expense("Coffee", 500, @t2)

      assert ExAutomerge.document_updated_at(doc) == @t2
    end

    test "reports the latest stamp even when a later edit carries an earlier time" do
      # Change times are advisory and can arrive out of order (device clock skew);
      # we surface the max, not the last-written value.
      doc =
        "Book"
        |> ExAutomerge.new_document(@t2)
        |> ExAutomerge.add_expense("Coffee", 500, @t1)

      assert ExAutomerge.document_updated_at(doc) == @t2
    end

    test "returns nil when no change carries a usable (non-zero) time" do
      doc = ExAutomerge.new_document("Book", 0)
      assert ExAutomerge.document_updated_at(doc) == nil
    end

    test "after a merge, reflects the most recent change from either side" do
      base = ExAutomerge.new_document("Book", @t1)

      fork_a = ExAutomerge.add_expense(base, "Lunch", 1200, @t1)
      fork_b = ExAutomerge.add_expense(base, "Bus", 250, @t2)

      merged = ExAutomerge.merge(fork_a, fork_b)
      assert ExAutomerge.document_updated_at(merged) == @t2
    end
  end

  describe "amount integer boundaries" do
    # Rust stores amount as i64. Rustler decodes Elixir integers to i64 when
    # calling into the NIF — values outside i64 range raise ArgumentError.
    # Elixir integers are arbitrary-precision, so the return direction is always safe.

    @i64_max 9_223_372_036_854_775_807
    @i64_min -9_223_372_036_854_775_808

    test "i64::MAX amount round-trips correctly" do
      doc =
        "Book" |> ExAutomerge.new_document(@t1) |> ExAutomerge.add_expense("Max", @i64_max, @t1)

      assert [%{amount: @i64_max}] = ExAutomerge.list_expenses(doc)
    end

    test "i64::MIN amount round-trips correctly" do
      doc =
        "Book" |> ExAutomerge.new_document(@t1) |> ExAutomerge.add_expense("Min", @i64_min, @t1)

      assert [%{amount: @i64_min}] = ExAutomerge.list_expenses(doc)
    end

    test "negative amounts are accepted (no validation yet)" do
      doc =
        "Book" |> ExAutomerge.new_document(@t1) |> ExAutomerge.add_expense("Refund", -500, @t1)

      assert [%{amount: -500}] = ExAutomerge.list_expenses(doc)
    end

    test "amount exceeding i64::MAX raises ArgumentError" do
      doc = ExAutomerge.new_document("Book", @t1)

      assert_raise ArgumentError, fn ->
        ExAutomerge.add_expense(doc, "Over", @i64_max + 1, @t1)
      end
    end
  end

  describe "merge/2" do
    test "merging two documents preserves expenses from both" do
      base =
        "Book" |> ExAutomerge.new_document(@t1) |> ExAutomerge.add_expense("Coffee", 500, @t1)

      fork_a = ExAutomerge.add_expense(base, "Lunch", 1200, @t1)
      fork_b = ExAutomerge.add_expense(base, "Bus", 250, @t1)

      descriptions =
        fork_a
        |> ExAutomerge.merge(fork_b)
        |> ExAutomerge.list_expenses()
        |> Enum.map(& &1.description)

      assert "Coffee" in descriptions
      assert "Lunch" in descriptions
      assert "Bus" in descriptions
      assert length(descriptions) == 3
    end

    test "merge is commutative for the resulting expense set" do
      base = ExAutomerge.new_document("Book", @t1)

      fork_a = ExAutomerge.add_expense(base, "A", 100, @t1)
      fork_b = ExAutomerge.add_expense(base, "B", 200, @t1)

      set_ab = fork_a |> ExAutomerge.merge(fork_b) |> ExAutomerge.list_expenses() |> MapSet.new()
      set_ba = fork_b |> ExAutomerge.merge(fork_a) |> ExAutomerge.list_expenses() |> MapSet.new()

      assert set_ab == set_ba
    end
  end
end
