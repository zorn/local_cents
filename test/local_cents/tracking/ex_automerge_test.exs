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

  defp expense(id, date, description, cost, category_id \\ nil) do
    %{id: id, date: date, description: description, cost: cost, category_id: category_id}
  end

  defp category(id, name), do: %{id: id, name: name}

  defp with_expenses(state, expenses), do: %{state | expenses: expenses}

  defp with_categories(state, categories), do: %{state | categories: categories}

  # The merged bytes alone, for tests asserting the combined document rather than the
  # conflict summary `merge/2` returns beside it.
  defp merge_bytes(left, right), do: elem(ExAutomerge.merge(left, right), 0)

  describe "new_document/2, document_name/1 and decode/1" do
    test "a new document carries its name and has no expenses" do
      doc = ExAutomerge.new_document("Family Expenses", @earlier)

      assert byte_size(doc) > 0
      assert ExAutomerge.document_name(doc) == "Family Expenses"
      assert ExAutomerge.decode(doc) == %{name: "Family Expenses", categories: [], expenses: []}
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

    test "round-trips categories and an expense's category_id" do
      doc = ExAutomerge.new_document("Book", @earlier)

      state =
        doc
        |> ExAutomerge.decode()
        |> with_categories([category("cat1", "Groceries")])
        |> with_expenses([expense("id1", "2026-07-11", "Coffee", "12.34", "cat1")])

      updated = ExAutomerge.reconcile(doc, state, @later)

      assert ExAutomerge.decode(updated) == state
    end
  end

  describe "merge/2 with categories" do
    test "a concurrent rename and delete of different categories merge by identity" do
      # The same identity-keyed merge guarantee expenses have (ADR 0015) applies to
      # categories: `#[key]` on the category `id` means one device renaming category
      # `a` and another deleting category `b` both survive the merge.
      base = ExAutomerge.new_document("Book", @earlier)

      base =
        ExAutomerge.reconcile(
          base,
          with_categories(ExAutomerge.decode(base), [
            category("a", "Groceries"),
            category("b", "Transit")
          ]),
          @earlier
        )

      # Device 1 renames category a.
      fork_1 =
        ExAutomerge.reconcile(
          base,
          with_categories(ExAutomerge.decode(base), [
            category("a", "Food"),
            category("b", "Transit")
          ]),
          @later
        )

      # Device 2 deletes category b.
      fork_2 =
        ExAutomerge.reconcile(
          base,
          with_categories(ExAutomerge.decode(base), [category("a", "Groceries")]),
          @later
        )

      by_id =
        fork_1
        |> merge_bytes(fork_2)
        |> ExAutomerge.decode()
        |> Map.fetch!(:categories)
        |> Map.new(&{&1.id, &1.name})

      assert by_id == %{"a" => "Food"}
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

      merged = merge_bytes(fork_a, fork_b)
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
        |> merge_bytes(fork_b)
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
        |> merge_bytes(fork_b)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> MapSet.new()

      set_ba =
        fork_b
        |> merge_bytes(fork_a)
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
        |> merge_bytes(fork_2)
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> Map.new(&{&1.id, &1})

      assert Enum.sort(Map.keys(by_id)) == ["a", "c"]
      refute Map.has_key?(by_id, "b")
      assert by_id["c"].description == "Train"
      assert by_id["c"].cost == "9.99"
    end
  end

  describe "sync protocol" do
    # Drives the Automerge sync exchange between two peers to completion: each peer
    # holds its own document bytes and a per-peer sync state, and the loop alternates
    # generate-then-receive on both sides until neither has a message left to send.
    # This is the same exchange the two-BEAM demo runs (ADR 0025), reduced to a pure
    # function so the assertions stay deterministic. It also totals the bytes of every
    # delivered message so a test can compare how much crossed the wire, returning
    # `{doc_a, doc_b, transferred_bytes}`.
    defp run_sync(doc_a, state_a, doc_b, state_b, transferred \\ 0) do
      # Both peers generate against the round's starting state before either delivers,
      # so termination is judged on the same state the messages were built from.
      # Receiving A's message into B first (then generating B) would leave B with a
      # fresh acknowledgment to send every round and the loop would never settle. The
      # state handles advance in place, so only the document bytes thread through.
      message_a = ExAutomerge.generate_sync_message(doc_a, state_a)
      message_b = ExAutomerge.generate_sync_message(doc_b, state_b)

      if is_nil(message_a) and is_nil(message_b) do
        {doc_a, doc_b, transferred}
      else
        doc_b =
          if message_a,
            do: ExAutomerge.receive_sync_message(doc_b, state_b, message_a),
            else: doc_b

        doc_a =
          if message_b,
            do: ExAutomerge.receive_sync_message(doc_a, state_a, message_b),
            else: doc_a

        transferred = transferred + message_bytes(message_a) + message_bytes(message_b)
        run_sync(doc_a, state_a, doc_b, state_b, transferred)
      end
    end

    defp message_bytes(nil), do: 0
    defp message_bytes(message), do: byte_size(message)

    test "generate_sync_message returns nil once a peer has nothing left to send" do
      doc = ExAutomerge.new_document("Book", @earlier)
      state = ExAutomerge.new_sync_state()

      # The first message always goes out so the remote learns this peer's heads;
      # with no reply and no new local changes, the next call has nothing to add.
      first_message = ExAutomerge.generate_sync_message(doc, state)
      assert byte_size(first_message) > 0
      assert ExAutomerge.generate_sync_message(doc, state) == nil
    end

    test "a reconcile after a small edit ships only the missing change, not the whole document" do
      base = ExAutomerge.new_document("Book", @earlier)

      expenses =
        for n <- 1..20, do: expense("id#{n}", "2026-07-11", "Expense number #{n}", "#{n}.00")

      # Peer A holds twenty expenses; peer B is still at the empty base. Their per-peer
      # sync states persist across both exchanges, which is what lets the second one
      # ship a delta instead of starting over.
      state_a = ExAutomerge.new_sync_state()
      state_b = ExAutomerge.new_sync_state()

      peer_a =
        ExAutomerge.reconcile(base, with_expenses(ExAutomerge.decode(base), expenses), @earlier)

      {peer_a, peer_b, full_sync_bytes} = run_sync(peer_a, state_a, base, state_b)

      # Both sides now match, and each state remembers the shared point. Peer A edits
      # one field of one expense.
      [first | rest] = ExAutomerge.decode(peer_a).expenses

      edited =
        ExAutomerge.reconcile(
          peer_a,
          with_expenses(ExAutomerge.decode(peer_a), [%{first | description: "Espresso"} | rest]),
          @later
        )

      {edited, peer_b, delta_bytes} = run_sync(edited, state_a, peer_b, state_b)

      assert full_sync_bytes > 0
      assert delta_bytes > 0
      # The one-field reconcile crosses far less than the initial full transfer and
      # less than the whole document — only the missing change went over the wire.
      assert delta_bytes < full_sync_bytes
      assert delta_bytes < byte_size(edited)
      assert ExAutomerge.decode(edited) == ExAutomerge.decode(peer_b)
    end

    test "two divergent documents converge to the same state" do
      base = ExAutomerge.new_document("Book", @earlier)

      base =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Coffee", nil),
            expense("b", "2026-07-11", "Lunch", nil)
          ]),
          @earlier
        )

      # Peer 1 edits expense a; peer 2 edits expense b. Neither has seen the other's
      # change when the exchange starts.
      peer_1 =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Espresso", "3.50"),
            expense("b", "2026-07-11", "Lunch", nil)
          ]),
          @later
        )

      peer_2 =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("a", "2026-07-11", "Coffee", nil),
            expense("b", "2026-07-11", "Dinner", "20.00")
          ]),
          @later
        )

      {converged_1, converged_2, _transferred} =
        run_sync(peer_1, ExAutomerge.new_sync_state(), peer_2, ExAutomerge.new_sync_state())

      by_id =
        converged_1
        |> ExAutomerge.decode()
        |> Map.fetch!(:expenses)
        |> Map.new(&{&1.id, &1})

      assert ExAutomerge.decode(converged_1) == ExAutomerge.decode(converged_2)
      assert by_id["a"].description == "Espresso"
      assert by_id["a"].cost == "3.50"
      assert by_id["b"].description == "Dinner"
      assert by_id["b"].cost == "20.00"
    end
  end

  describe "merge/2 conflict summary" do
    # A base document holding one expense "x", the subject of every conflict below.
    # Both sides diverge from this common ancestor.
    defp base_with_one_expense do
      base = ExAutomerge.new_document("Book", @earlier)

      ExAutomerge.reconcile(
        base,
        with_expenses(ExAutomerge.decode(base), [expense("x", "2026-07-11", "Original", nil)]),
        @earlier
      )
    end

    # Reconciles a new `description` onto expense `id`, stamped `time`, leaving the
    # rest of the document untouched. Each call loads the prior document afresh, so
    # two calls off the same base produce two concurrent (conflicting) edits.
    defp edit_description(doc, id, description, time) do
      state = ExAutomerge.decode(doc)

      expenses =
        Enum.map(state.expenses, fn
          %{id: ^id} = expense -> %{expense | description: description}
          expense -> expense
        end)

      ExAutomerge.reconcile(doc, with_expenses(state, expenses), time)
    end

    test "a merge with no concurrent edits reports an empty summary" do
      base = base_with_one_expense()
      # A linear descendant, so nothing conflicts.
      descendant = edit_description(base, "x", "Renamed", @later)

      {_merged, summary} = ExAutomerge.merge(base, descendant)

      assert summary == %{field_conflicts: [], edit_delete_conflicts: []}
    end

    test "concurrent edits to one field surface as one kept value plus alternatives, each with provenance" do
      base = base_with_one_expense()
      fork_a = edit_description(base, "x", "A", 1_700_000_100)
      fork_b = edit_description(base, "x", "B", 1_700_000_200)

      {_merged, summary} = ExAutomerge.merge(fork_a, fork_b)

      assert [conflict] = summary.field_conflicts
      assert conflict.expense_id == "x"
      assert conflict.field == "description"
      assert summary.edit_delete_conflicts == []

      values = [conflict.kept | conflict.alternatives]
      assert length(conflict.alternatives) == 1

      # Which value wins is chosen by Automerge op id (an arbitrary actor tiebreak for
      # genuinely concurrent edits), so assert the set of surfaced values and each
      # value's provenance rather than which one was kept.
      assert values |> Enum.map(& &1.value) |> Enum.sort() == ["A", "B"]

      assert Map.new(values, &{&1.value, &1.time}) == %{
               "A" => 1_700_000_100,
               "B" => 1_700_000_200
             }

      assert Enum.all?(values, &(is_binary(&1.device) and &1.device != ""))
      assert values |> Enum.map(& &1.device) |> Enum.uniq() |> length() == 2
    end

    test "three concurrent edits to one field surface all alternatives, not just two" do
      base = base_with_one_expense()
      fork_a = edit_description(base, "x", "A", 1_700_000_100)
      fork_b = edit_description(base, "x", "B", 1_700_000_200)
      fork_c = edit_description(base, "x", "C", 1_700_000_300)

      {merged_ab, _} = ExAutomerge.merge(fork_a, fork_b)
      {_merged, summary} = ExAutomerge.merge(merged_ab, fork_c)

      assert [conflict] = summary.field_conflicts
      assert length(conflict.alternatives) == 2

      values = [conflict.kept | conflict.alternatives]
      assert values |> Enum.map(& &1.value) |> Enum.sort() == ["A", "B", "C"]

      assert Map.new(values, &{&1.value, &1.time}) ==
               %{"A" => 1_700_000_100, "B" => 1_700_000_200, "C" => 1_700_000_300}
    end

    test "an expense edited on one side and deleted on the other resolves to the delete but surfaces the dropped edit" do
      base = base_with_one_expense()

      edited = edit_description(base, "x", "Edited on A", 1_700_000_100)

      deleted =
        ExAutomerge.reconcile(base, with_expenses(ExAutomerge.decode(base), []), 1_700_000_200)

      {merged, summary} = ExAutomerge.merge(edited, deleted)

      # The delete wins: x is gone from the reconciled document.
      assert ExAutomerge.decode(merged).expenses == []
      assert summary.field_conflicts == []

      # The dropped edit is still surfaced, not lost.
      assert [conflict] = summary.edit_delete_conflicts
      assert conflict.expense_id == "x"
      assert conflict.expense.description == "Edited on A"
      assert conflict.time == 1_700_000_100
      assert is_binary(conflict.device) and conflict.device != ""
    end

    test "a one-sided delete with the surviving side untouched surfaces no edit-vs-delete conflict" do
      # The surviving side branched but never touched x, so without the common ancestor the
      # merge-time diff would flag x's drop as a lost edit when it is a plain delete.
      base = ExAutomerge.new_document("Book", @earlier)

      base =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [
            expense("x", "2026-07-11", "Coffee", nil),
            expense("y", "2026-07-11", "Lunch", nil)
          ]),
          @earlier
        )

      deleted =
        ExAutomerge.reconcile(
          base,
          with_expenses(ExAutomerge.decode(base), [expense("y", "2026-07-11", "Lunch", nil)]),
          1_700_000_200
        )

      survivor = edit_description(base, "y", "Dinner", 1_700_000_100)

      {merged, summary} = ExAutomerge.merge(survivor, deleted)

      assert Enum.map(ExAutomerge.decode(merged).expenses, & &1.id) == ["y"]
      assert summary == %{field_conflicts: [], edit_delete_conflicts: []}
    end
  end

  describe "conflict_summary/2" do
    # The sync path's conflict read: given the document as it stood before a sync
    # message and the document after folding that message in, report what conflicted.
    # Field conflicts read from the register the merged document already carries;
    # edit-vs-delete reads from the prior side an incoming delete dropped an edit from.

    test "a linear descendant reports an empty summary" do
      base = base_with_one_expense()
      merged = edit_description(base, "x", "Renamed", @later)

      assert ExAutomerge.conflict_summary(base, merged) ==
               %{field_conflicts: [], edit_delete_conflicts: []}
    end

    test "a concurrent edit folded in surfaces as one kept value plus alternatives" do
      base = base_with_one_expense()
      prior = edit_description(base, "x", "A", 1_700_000_100)
      incoming = edit_description(base, "x", "B", 1_700_000_200)
      {merged, _} = ExAutomerge.merge(prior, incoming)

      summary = ExAutomerge.conflict_summary(prior, merged)

      assert [conflict] = summary.field_conflicts
      assert conflict.expense_id == "x"
      assert conflict.field == "description"
      assert summary.edit_delete_conflicts == []

      values = [conflict.kept | conflict.alternatives]
      assert values |> Enum.map(& &1.value) |> Enum.sort() == ["A", "B"]

      assert Map.new(values, &{&1.value, &1.time}) ==
               %{"A" => 1_700_000_100, "B" => 1_700_000_200}
    end

    test "an incoming delete of an expense edited here surfaces the dropped edit" do
      base = base_with_one_expense()
      prior = edit_description(base, "x", "Edited here", 1_700_000_100)

      deleted =
        ExAutomerge.reconcile(base, with_expenses(ExAutomerge.decode(base), []), 1_700_000_200)

      {merged, _} = ExAutomerge.merge(prior, deleted)

      summary = ExAutomerge.conflict_summary(prior, merged)

      assert summary.field_conflicts == []
      assert [conflict] = summary.edit_delete_conflicts
      assert conflict.expense_id == "x"
      assert conflict.expense.description == "Edited here"
      assert conflict.time == 1_700_000_100
    end

    test "an incoming delete of an expense untouched here surfaces no edit-vs-delete conflict" do
      base = base_with_one_expense()

      deleted =
        ExAutomerge.reconcile(base, with_expenses(ExAutomerge.decode(base), []), 1_700_000_200)

      {merged, _} = ExAutomerge.merge(base, deleted)

      assert ExAutomerge.conflict_summary(base, merged) ==
               %{field_conflicts: [], edit_delete_conflicts: []}
    end
  end
end
