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

  alias LocalCents.Tracking

  @moduletag :tmp_dir

  test "two peers that diverged independently converge to the same expenses", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: dir)
    coffee = add_expense(book.id, "Coffee")
    lunch = add_expense(book.id, "Lunch")

    # A second peer forks from the shared ancestor holding both expenses.
    peer_b = fork_peer(dir, book.id)

    # The link is suspended (we simply do not reconcile): each peer edits a
    # different expense with no knowledge of the other's change.
    edit_description(book.id, coffee.id, "Espresso")
    edit_description(peer_b, lunch.id, "Dinner")

    reconcile(book.id, peer_b)

    assert descriptions_by_id(book.id) == descriptions_by_id(peer_b)
    assert descriptions_by_id(book.id) == %{coffee.id => "Espresso", lunch.id => "Dinner"}
  end

  test "a reconcile after a small edit ships only the missing change, not the whole document",
       %{tmp_dir: dir} do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: dir)

    # Peer B forks from the empty common ancestor, before A diverges — so the two
    # share the root document objects and their edits merge into one expenses list
    # rather than conflicting at the container. A then adds twenty expenses B has
    # never seen, so the first reconcile is a full transfer: the baseline the delta is
    # measured against. The peers keep their per-peer sync state between the two
    # reconciles, which is what lets the second ship a delta instead of starting over.
    peer_b = fork_peer(dir, book_a.id)
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

  test "after a reconcile, Last Updated reflects the latest edit across both peers", %{
    tmp_dir: dir
  } do
    earlier = ~U[2026-01-01 00:00:00Z]
    later = ~U[2026-06-01 00:00:00Z]

    {:ok, book_a} = Tracking.create_book("Family", books_dir: dir, now: earlier)
    {:ok, coffee} = Tracking.add_expense(book_a.id, %{description: "Coffee"}, now: earlier)

    peer_b = fork_peer(dir, book_a.id)

    # Peer B makes a later edit that A has not seen; A's own latest write is `earlier`.
    {:ok, _} = Tracking.edit_expense(peer_b, coffee.id, %{description: "Espresso"}, now: later)

    assert Tracking.get_book(book_a.id, books_dir: dir).updated_at == earlier

    reconcile(book_a.id, peer_b)

    # A now carries B's later change, so its Last Updated is the newer edit across the
    # two peers, not A's latest local write (ADR 0012).
    assert Tracking.get_book(book_a.id, books_dir: dir).updated_at == later
    assert Tracking.get_book(peer_b, books_dir: dir).updated_at == later
  end

  test "peers that diverged across an offline period reconnect and converge", %{tmp_dir: dir} do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: dir)
    coffee = add_expense(book_a.id, "Coffee")
    lunch = add_expense(book_a.id, "Lunch")

    peer_b = fork_peer(dir, book_a.id)

    # Simulate peer B's offline period with a clean close — never a brutal kill of a
    # supervised server. Through the context, B now reads as not open.
    :ok = Tracking.close_book(peer_b)
    assert {:error, :not_open} = Tracking.list_expenses(peer_b)

    # A keeps editing while B is away.
    edit_description(book_a.id, coffee.id, "Espresso")

    # B comes back and makes its own independent edit. Its sync state was dropped by the
    # close, so the reconnect drives a fresh exchange.
    :ok = Tracking.open_book(peer_b, books_dir: dir)
    edit_description(peer_b, lunch.id, "Dinner")

    reconcile(book_a.id, peer_b)

    assert descriptions_by_id(book_a.id) == descriptions_by_id(peer_b)
    assert descriptions_by_id(book_a.id) == %{coffee.id => "Espresso", lunch.id => "Dinner"}
  end

  test "a reconcile that carries a peer's category change signals category subscribers", %{
    tmp_dir: dir
  } do
    {:ok, book_a} = Tracking.create_book("Family", books_dir: dir)
    book_id = book_a.id
    peer_b = fork_peer(dir, book_id)

    # Peer B adds a category A has never seen. A view refreshes its category picker
    # only on `:categories_updated` (ADR 0018), so a reconcile that lands the category
    # under `:book_updated` alone would leave that picker stale.
    {:ok, _} = Tracking.add_category(peer_b, %{name: "Groceries"})

    :ok = Tracking.subscribe(book_id)
    reconcile(book_id, peer_b)

    assert_receive {:categories_updated, ^book_id}
    assert [%Tracking.Category{name: "Groceries"}] = Tracking.list_categories(book_id)
  end

  # Drives the Automerge sync exchange between two open peers to completion, purely
  # through the context. Each round both peers generate a message against their
  # current document before either delivers, so termination is judged on the same
  # state the messages were built from; the exchange settles once neither peer has a
  # message left to send. Returns the total bytes delivered, so a test can compare
  # how much crossed the wire between reconciles.
  defp reconcile(peer_a, peer_b, transferred \\ 0) do
    message_a = Tracking.generate_sync_message(peer_a, peer_b)
    message_b = Tracking.generate_sync_message(peer_b, peer_a)

    if is_nil(message_a) and is_nil(message_b) do
      transferred
    else
      if message_a, do: :ok = Tracking.receive_sync_message(peer_b, peer_a, message_a)
      if message_b, do: :ok = Tracking.receive_sync_message(peer_a, peer_b, message_b)

      reconcile(peer_a, peer_b, transferred + message_bytes(message_a) + message_bytes(message_b))
    end
  end

  defp message_bytes(nil), do: 0
  defp message_bytes(message), do: byte_size(message)

  # Forks `source_id`'s document into a second open Book in the same directory, so
  # the two peers share a genuine common ancestor (identical bytes, identical
  # Automerge history). This is the "both start from a common ancestor" the demo
  # seeds over the sync link, reduced to a file fork so the shared starting point is
  # deterministic.
  defp fork_peer(dir, source_id) do
    new_id = Ecto.UUID.generate()
    File.cp!(Path.join(dir, source_id <> ".lcbook"), Path.join(dir, new_id <> ".lcbook"))
    :ok = Tracking.open_book(new_id, books_dir: dir)
    new_id
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
