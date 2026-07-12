defmodule LocalCents.Tracking.ExAutomergeTest do
  # Exercises the Rust NIF boundary directly as a codec: document creation, the Book
  # name that lives inside the document, decode/reconcile round-tripping (including a
  # decimal-string cost and an absent cost), the change-time "last updated"
  # derivation, and CRDT merge. Domain rules live in `BookDocument`; higher-level
  # behavior is covered through `LocalCents.Tracking`.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.ExAutomerge

  # Fixed unix-seconds stamps for deterministic change times. `@later` is later than
  # `@earlier` so tests can assert the "most recent" behavior.
  @earlier 1_700_000_000
  @later 1_700_000_500

  defp expense(id, date, description, cost) do
    %{id: id, date: date, description: description, cost: cost}
  end

  defp with_expenses(state, expenses), do: %{state | expenses: expenses}

  describe "new_document/2, document_name/1 and decode/1" do
    test "a new document carries its name and has no expenses" do
      doc = ExAutomerge.new_document("Family Expenses", @earlier)

      assert byte_size(doc) > 0
      assert ExAutomerge.document_name(doc) == "Family Expenses"
      assert ExAutomerge.decode(doc) == %{name: "Family Expenses", expenses: []}
    end

    test "decode raises ArgumentError on bytes that are not a valid document" do
      assert_raise ArgumentError, fn -> ExAutomerge.decode("garbage") end
    end
  end

  describe "reconcile/3" do
    test "reconciles a new state onto the prior bytes and round-trips it" do
      doc = ExAutomerge.new_document("Book", @earlier)

      state =
        doc
        |> ExAutomerge.decode()
        |> with_expenses([expense("id1", "2026-07-11", "Coffee", "12.34")])

      updated = ExAutomerge.reconcile(doc, state, @later)

      assert ExAutomerge.decode(updated) == state
    end

    test "an absent cost round-trips as nil" do
      doc = ExAutomerge.new_document("Book", @earlier)

      state =
        doc
        |> ExAutomerge.decode()
        |> with_expenses([expense("id1", "2026-07-11", "Gift", nil)])

      updated = ExAutomerge.reconcile(doc, state, @later)

      assert %{expenses: [%{cost: nil}]} = ExAutomerge.decode(updated)
    end

    test "a rename via new state preserves expenses" do
      doc = ExAutomerge.new_document("Old Name", @earlier)

      with_expense =
        ExAutomerge.reconcile(
          doc,
          with_expenses(ExAutomerge.decode(doc), [expense("id1", "2026-07-11", "Coffee", "5.00")]),
          @earlier
        )

      renamed =
        ExAutomerge.reconcile(
          with_expense,
          %{ExAutomerge.decode(with_expense) | name: "New Name"},
          @later
        )

      assert %{name: "New Name", expenses: [%{description: "Coffee"}]} =
               ExAutomerge.decode(renamed)
    end
  end

  describe "document_updated_at/1" do
    defp apply_expense(doc, description, time) do
      state =
        doc
        |> ExAutomerge.decode()
        |> with_expenses([expense("id-#{description}", "2026-07-11", description, nil)])

      ExAutomerge.reconcile(doc, state, time)
    end

    test "a new document reports the time it was created with" do
      doc = ExAutomerge.new_document("Book", @earlier)
      assert ExAutomerge.document_updated_at(doc) == @earlier
    end

    test "reports the time of the most recent change" do
      doc = "Book" |> ExAutomerge.new_document(@earlier) |> apply_expense("Coffee", @later)
      assert ExAutomerge.document_updated_at(doc) == @later
    end

    test "reports the latest stamp even when a later edit carries an earlier time" do
      # Change times are advisory and can arrive out of order (device clock skew);
      # we surface the max, not the last-written value.
      doc = "Book" |> ExAutomerge.new_document(@later) |> apply_expense("Coffee", @earlier)
      assert ExAutomerge.document_updated_at(doc) == @later
    end

    test "returns nil when no change carries a usable (non-zero) time" do
      doc = ExAutomerge.new_document("Book", 0)
      assert ExAutomerge.document_updated_at(doc) == nil
    end

    test "after a merge, reflects the most recent change from either side" do
      base = ExAutomerge.new_document("Book", @earlier)

      fork_a = apply_expense(base, "Lunch", @earlier)
      fork_b = apply_expense(base, "Bus", @later)

      merged = ExAutomerge.merge(fork_a, fork_b)
      assert ExAutomerge.document_updated_at(merged) == @later
    end
  end

  describe "merge/2" do
    defp fork(doc, id, description, time) do
      state =
        doc
        |> ExAutomerge.decode()
        |> with_expenses([expense(id, "2026-07-11", description, nil)])

      ExAutomerge.reconcile(doc, state, time)
    end

    test "merging two documents preserves expenses from both" do
      base = ExAutomerge.new_document("Book", @earlier)

      fork_a = fork(base, "a", "Lunch", @earlier)
      fork_b = fork(base, "b", "Bus", @earlier)

      descriptions =
        fork_a
        |> ExAutomerge.merge(fork_b)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> Enum.map(& &1.description)

      assert "Lunch" in descriptions
      assert "Bus" in descriptions
      assert length(descriptions) == 2
    end

    test "merge is commutative for the resulting expense set" do
      base = ExAutomerge.new_document("Book", @earlier)

      fork_a = fork(base, "a", "A", @earlier)
      fork_b = fork(base, "b", "B", @earlier)

      set_ab =
        fork_a
        |> ExAutomerge.merge(fork_b)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> MapSet.new()

      set_ba =
        fork_b
        |> ExAutomerge.merge(fork_a)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> MapSet.new()

      assert set_ab == set_ba
    end

    test "a concurrent delete and edit of different expenses merge without corruption" do
      # The regression this locks in: because each expense is keyed by its `id`
      # (ADR 0015), autosurgeon matches list items by identity, not position. So one
      # device deleting the middle expense and another editing a *different* one
      # both survive the merge. Position-based matching would rewrite the wrong
      # objects and lose the concurrent edit.
      base = ExAutomerge.new_document("Book", @earlier)

      base =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Coffee", nil),
            expense("b", "2026-07-11", "Lunch", nil),
            expense("c", "2026-07-11", "Bus", nil)
          ]),
          @earlier
        )

      # Device 1 deletes the middle expense (b).
      fork_1 =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Coffee", nil),
            expense("c", "2026-07-11", "Bus", nil)
          ]),
          @later
        )

      # Device 2 edits a different expense (c), changing its description and cost.
      fork_2 =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Coffee", nil),
            expense("b", "2026-07-11", "Lunch", nil),
            expense("c", "2026-07-11", "Train", "9.99")
          ]),
          @later
        )

      by_id =
        fork_1
        |> ExAutomerge.merge(fork_2)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> Map.new(&{&1.id, &1})

      assert Enum.sort(Map.keys(by_id)) == ["a", "c"]
      refute Map.has_key?(by_id, "b")
      assert by_id["c"].description == "Train"
      assert by_id["c"].cost == "9.99"
    end
  end
end
