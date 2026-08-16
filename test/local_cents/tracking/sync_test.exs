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
