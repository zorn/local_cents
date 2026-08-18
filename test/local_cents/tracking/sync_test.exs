defmodule LocalCents.Tracking.SyncTest do
  # Proves the two-peer reconcile behavior at the `Tracking`/`BookServer` seam:
  # two open Books fork from a common ancestor, diverge while their link is
  # suspended, then a sync exchange brings them back together. Everything is
  # asserted through the `LocalCents.Tracking` context — the reconcile is observed
  # the way a real caller sees it, never through a NIF side channel. The real
  # Phoenix Channel between two OS processes lands in a later ticket; here a plain
  # loop stands in for the transport.
  #
  # Async: each test seeds its Books into its own `:tmp_dir`, so no shared
  # `:books_dir` env forces serialization.
  use ExUnit.Case, async: true

  import LocalCents.SyncTestHelper
  import TinyMaps

  alias LocalCents.Tracking

  @moduletag :tmp_dir

  test "two peers that diverged independently converge to the same expenses", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")
    lunch = add_expense(book.id, "Lunch")

    # A second peer forks from the shared ancestor holding both expenses.
    peer_b = fork_peer(tmp_dir, book.id)

    # The link is suspended (we simply do not reconcile): each peer edits a
    # different expense with no knowledge of the other's change.
    edit_description(book.id, coffee.id, "Espresso")
    edit_description(peer_b, lunch.id, "Dinner")

    reconcile(book.id, peer_b)

    assert descriptions_by_id(book.id) == descriptions_by_id(peer_b)
    assert descriptions_by_id(book.id) == %{coffee.id => "Espresso", lunch.id => "Dinner"}
  end

  test "a reconcile after a small edit ships only the missing change, not the whole document",
       ~M{tmp_dir} do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: tmp_dir)

    # Peer B forks from the empty common ancestor, before A diverges — so the two
    # share the root document objects and their edits merge into one expenses list
    # rather than conflicting at the container. A then adds twenty expenses B has
    # never seen, so the first reconcile is a full transfer: the baseline the delta is
    # measured against. The peers keep their per-peer sync state between the two
    # reconciles, which is what lets the second ship a delta instead of starting over.
    peer_b = fork_peer(tmp_dir, book_a.id)
    for n <- 1..20, do: add_expense(book_a.id, "Expense number #{n}")

    full_sync_bytes = reconcile(book_a.id, peer_b)

    # Peer A edits one field of one expense.
    [expense | _] = Tracking.list_expenses(book_a.id)
    edit_description(book_a.id, expense.id, "Espresso")

    delta_bytes = reconcile(book_a.id, peer_b)

    assert full_sync_bytes > 0
    assert delta_bytes > 0
    # The one-field edit crosses far less than seeding all twenty expenses did: only
    # the missing change went over the wire, not the whole document.
    assert delta_bytes < full_sync_bytes
    assert descriptions_by_id(book_a.id) == descriptions_by_id(peer_b)
    assert Map.fetch!(descriptions_by_id(peer_b), expense.id) == "Espresso"
  end

  test "after a reconcile, Last Updated reflects the latest edit across both peers",
       ~M{tmp_dir} do
    earlier = ~U[2026-01-01 00:00:00Z]
    later = ~U[2026-06-01 00:00:00Z]

    {:ok, book_a} = Tracking.create_book("Family", books_dir: tmp_dir, now: earlier)
    {:ok, coffee} = Tracking.add_expense(book_a.id, %{description: "Coffee"}, now: earlier)

    peer_b = fork_peer(tmp_dir, book_a.id)

    # Peer B makes a later edit that A has not seen; A's own latest write is `earlier`.
    {:ok, _} = Tracking.edit_expense(peer_b, coffee.id, %{description: "Espresso"}, now: later)

    assert Tracking.get_book(book_a.id, books_dir: tmp_dir).updated_at == earlier

    reconcile(book_a.id, peer_b)

    # A now carries B's later change, so its Last Updated is the newer edit across the
    # two peers, not A's latest local write (ADR 0012).
    assert Tracking.get_book(book_a.id, books_dir: tmp_dir).updated_at == later
    assert Tracking.get_book(peer_b, books_dir: tmp_dir).updated_at == later
  end

  test "peers that diverged across an offline period reconnect and converge", ~M{tmp_dir} do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book_a.id, "Coffee")
    lunch = add_expense(book_a.id, "Lunch")

    peer_b = fork_peer(tmp_dir, book_a.id)

    # Simulate peer B's offline period with a clean close — never a brutal kill of a
    # supervised server. Through the context, B now reads as not open.
    :ok = Tracking.close_book(peer_b)
    assert {:error, :not_open} = Tracking.list_expenses(peer_b)

    # A keeps editing while B is away.
    edit_description(book_a.id, coffee.id, "Espresso")

    # B comes back and makes its own independent edit. Its sync state was dropped by the
    # close, so the reconnect drives a fresh exchange.
    :ok = Tracking.open_book(peer_b, books_dir: tmp_dir)
    edit_description(peer_b, lunch.id, "Dinner")

    reconcile(book_a.id, peer_b)

    assert descriptions_by_id(book_a.id) == descriptions_by_id(peer_b)
    assert descriptions_by_id(book_a.id) == %{coffee.id => "Espresso", lunch.id => "Dinner"}
  end

  test "a reconcile that carries a peer's category change signals category subscribers",
       ~M{tmp_dir} do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: tmp_dir)
    book_id = book_a.id
    peer_b = fork_peer(tmp_dir, book_id)

    # Peer B adds a category A has never seen. A view refreshes its category picker
    # only on `:categories_updated` (ADR 0018), so a reconcile that lands the category
    # under `:book_updated` alone would leave that picker stale.
    {:ok, _} = Tracking.add_category(peer_b, %{name: "Groceries"})

    :ok = Tracking.subscribe(book_id)
    reconcile(book_id, peer_b)

    assert_receive {:categories_updated, ^book_id}
    assert [%Tracking.Category{name: "Groceries"}] = Tracking.list_categories(book_id)
  end

  test "an open Book with no synced conflicts reports an empty conflict summary", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    add_expense(book.id, "Coffee")

    assert Tracking.conflict_summary(book.id) ==
             %{field_conflicts: [], edit_delete_conflicts: []}
  end

  test "concurrent edits to one expense's description surface through the context after a reconcile",
       ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")

    peer_b = fork_peer(tmp_dir, book.id)

    # The link is suspended: both peers retitle the same expense with no knowledge of
    # the other's edit.
    edit_description(book.id, coffee.id, "Espresso")
    edit_description(peer_b, coffee.id, "Latte")

    reconcile(book.id, peer_b)

    # Automerge picks one winner but keeps the loser; the conflict surfaces on both
    # peers, each having folded in the other's edit.
    for peer <- [book.id, peer_b] do
      assert %{field_conflicts: [conflict], edit_delete_conflicts: []} =
               Tracking.conflict_summary(peer)

      assert conflict.expense_id == coffee.id
      assert conflict.field == "description"

      values = [conflict.kept | conflict.alternatives]
      assert values |> Enum.map(& &1.value) |> Enum.sort() == ["Espresso", "Latte"]
    end
  end

  test "dismissing conflicts clears a surfaced summary back to empty", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")

    peer_b = fork_peer(tmp_dir, book.id)

    edit_description(book.id, coffee.id, "Espresso")
    edit_description(peer_b, coffee.id, "Latte")

    reconcile(book.id, peer_b)

    assert %{field_conflicts: [_conflict]} = Tracking.conflict_summary(book.id)

    assert :ok = Tracking.dismiss_conflicts(book.id)

    assert Tracking.conflict_summary(book.id) ==
             %{field_conflicts: [], edit_delete_conflicts: []}
  end

  test "dismissing one field conflict clears just that one and leaves the others",
       ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")
    lunch = add_expense(book.id, "Lunch")

    peer_b = fork_peer(tmp_dir, book.id)

    # Both expenses are retitled on both peers across the suspended link, so the
    # reconcile surfaces two separate scalar conflicts.
    edit_description(book.id, coffee.id, "Espresso")
    edit_description(peer_b, coffee.id, "Latte")
    edit_description(book.id, lunch.id, "Dinner")
    edit_description(peer_b, lunch.id, "Supper")

    reconcile(book.id, peer_b)

    assert %{field_conflicts: conflicts} = Tracking.conflict_summary(book.id)
    assert length(conflicts) == 2

    # Dismissing the coffee conflict leaves the lunch conflict standing — the user
    # grinds through a batch one at a time.
    assert :ok = Tracking.dismiss_field_conflict(book.id, coffee.id, "description")

    assert %{field_conflicts: [remaining], edit_delete_conflicts: []} =
             Tracking.conflict_summary(book.id)

    assert remaining.expense_id == lunch.id
  end

  test "an expense edited here and deleted on the other peer surfaces as an edit-vs-delete conflict",
       ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")

    peer_b = fork_peer(tmp_dir, book.id)

    # The link is suspended: this side edits the expense while the other deletes it.
    edit_description(book.id, coffee.id, "Espresso")
    :ok = Tracking.delete_expense(peer_b, coffee.id)

    reconcile(book.id, peer_b)

    # The delete wins, so the expense is gone from both peers, but this side's dropped
    # edit surfaces so the user can restore it rather than lose the work silently.
    assert %{field_conflicts: [], edit_delete_conflicts: [conflict]} =
             Tracking.conflict_summary(book.id)

    assert conflict.expense_id == coffee.id
    assert conflict.expense.description == "Espresso"
    assert expense(book.id, coffee.id) == nil
  end

  test "a delete on the other peer with no edit here reconciles silently", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")

    peer_b = fork_peer(tmp_dir, book.id)

    # The link is suspended: the other peer deletes the expense while this side
    # leaves it untouched. There is no lost edit, so nothing to decide.
    :ok = Tracking.delete_expense(peer_b, coffee.id)

    reconcile(book.id, peer_b)

    assert expense(book.id, coffee.id) == nil

    assert Tracking.conflict_summary(book.id) ==
             %{field_conflicts: [], edit_delete_conflicts: []}
  end

  test "keeping a delete acknowledges just that dropped edit and leaves the others",
       ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")
    lunch = add_expense(book.id, "Lunch")

    peer_b = fork_peer(tmp_dir, book.id)

    # Both expenses are edited here and deleted on the other peer, so the reconcile
    # surfaces two separate edit-vs-delete conflicts.
    edit_description(book.id, coffee.id, "Espresso")
    edit_description(book.id, lunch.id, "Dinner")
    :ok = Tracking.delete_expense(peer_b, coffee.id)
    :ok = Tracking.delete_expense(peer_b, lunch.id)

    reconcile(book.id, peer_b)

    assert %{edit_delete_conflicts: conflicts} = Tracking.conflict_summary(book.id)
    assert length(conflicts) == 2

    # Keeping the coffee delete clears just that decision, leaving the lunch one standing.
    assert :ok = Tracking.keep_deleted(book.id, coffee.id)

    assert %{field_conflicts: [], edit_delete_conflicts: [remaining]} =
             Tracking.conflict_summary(book.id)

    assert remaining.expense_id == lunch.id
  end

  test "restoring a dropped edit revives the expense and clears its decision", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    coffee = add_expense(book.id, "Coffee")

    peer_b = fork_peer(tmp_dir, book.id)

    edit_description(book.id, coffee.id, "Espresso")
    :ok = Tracking.delete_expense(peer_b, coffee.id)

    reconcile(book.id, peer_b)

    assert %{edit_delete_conflicts: [_conflict]} = Tracking.conflict_summary(book.id)

    # Restore brings the expense back with the edit that was dropped, and the decision clears.
    assert {:ok, restored} = Tracking.restore_expense(book.id, coffee.id)
    assert restored.id == coffee.id
    assert restored.description == "Espresso"

    assert expense(book.id, coffee.id).description == "Espresso"

    assert Tracking.conflict_summary(book.id) ==
             %{field_conflicts: [], edit_delete_conflicts: []}
  end

  test "restoring an expense whose category was deleted meanwhile revives it Uncategorized",
       ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    {:ok, groceries} = Tracking.add_category(book.id, %{name: "Groceries"})
    coffee = add_expense(book.id, "Coffee")
    {:ok, _} = Tracking.assign_category(book.id, coffee.id, groceries.id)

    peer_b = fork_peer(tmp_dir, book.id)

    # This side edits the filed expense; the other deletes it. Then the category it was filed
    # under is deleted here too, so reviving its old category_id would leave a dangling id.
    edit_description(book.id, coffee.id, "Espresso")
    :ok = Tracking.delete_expense(peer_b, coffee.id)
    reconcile(book.id, peer_b)
    :ok = Tracking.delete_category(book.id, groceries.id)

    assert {:ok, restored} = Tracking.restore_expense(book.id, coffee.id)
    assert restored.description == "Espresso"
    assert restored.category_id == nil
  end

  defp add_expense(id, description) do
    {:ok, expense} = Tracking.add_expense(id, %{description: description, cost: "1.00"})
    expense
  end

  defp edit_description(id, expense_id, description) do
    {:ok, expense} = Tracking.edit_expense(id, expense_id, %{description: description})
    expense
  end

  defp descriptions_by_id(id) do
    id
    |> Tracking.list_expenses()
    |> Map.new(&{&1.id, &1.description})
  end
end
