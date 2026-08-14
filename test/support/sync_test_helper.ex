defmodule LocalCents.SyncTestHelper do
  @moduledoc """
  Shared setup for the two-peer sync tests: forking a Book into a second open peer
  that shares its Automerge ancestor, and reading one expense back by id.

  Used across the context-level `LocalCents.Tracking.SyncTest` and the transport tests
  under `LocalCentsWeb.Sync`, which all diverge two peers from a common ancestor and
  then assert on what crossed between them.
  """

  # Its own top-level boundary rather than a member of the `LocalCents` core: this is
  # test-support scaffolding that happens to sit in the domain namespace, so it declares
  # the `LocalCents.Tracking` dependency it needs rather than the core gaining one on its
  # behalf (mirrors `LocalCents.BooksDirHelper`).
  use Boundary, top_level?: true, deps: [LocalCents.Tracking]

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.Expense

  @doc """
  Forks `source_id`'s document into a second open Book in the same `dir`, so the two
  peers share a genuine common ancestor — identical bytes, identical Automerge history.
  Returns the new Book's id.

  This is the "both start from a common ancestor" the demo seeds over the sync link,
  reduced to a file fork so the shared starting point is deterministic.
  """
  @spec fork_peer(dir :: String.t(), source_id :: Book.id()) :: Book.id()
  def fork_peer(dir, source_id) do
    new_id = Ecto.UUID.generate()
    File.cp!(Path.join(dir, source_id <> ".lcbook"), Path.join(dir, new_id <> ".lcbook"))
    :ok = Tracking.open_book(new_id, books_dir: dir)
    new_id
  end

  @doc "Returns the open Book's expense with `expense_id`, or `nil` when it holds none."
  @spec expense(Book.id(), Expense.id()) :: Expense.t() | nil
  def expense(book_id, expense_id) do
    book_id
    |> Tracking.list_expenses()
    |> Enum.find(&(&1.id == expense_id))
  end
end
