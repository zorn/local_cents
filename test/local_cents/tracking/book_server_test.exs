defmodule LocalCents.Tracking.BookServerTest do
  # Async: each test seeds its Book into its own `:tmp_dir` (injected via
  # create_book/open_book), so no shared `:books_dir` env forces serialization.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking
  alias LocalCents.Tracking.BookServer

  @moduletag :tmp_dir

  test "a command broadcasts {:book_updated, id} to subscribers", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", dir)
    :ok = Tracking.subscribe(book.id)

    {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

    assert_receive {:book_updated, id}
    assert id == book.id
  end

  test "a failed persist returns an error, keeps state, and does not broadcast", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", dir)
    :ok = Tracking.subscribe(book.id)

    # Make the books directory read-only so the atomic write (temp file + rename)
    # cannot create its temp file (non-root).
    File.chmod!(dir, 0o555)

    assert {:error, _reason} =
             Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

    # Restore write access so the temp-dir cleanup can remove the directory.
    File.chmod!(dir, 0o755)

    # Persist-then-commit: the in-memory document was not updated, no broadcast fired,
    # and the server stayed alive rather than crashing and losing the change.
    refute_receive {:book_updated, _}, 50
    assert Tracking.list_expenses(book.id) == []
    assert BookServer.alive?(book.id)
  end

  test "an invalid command returns a changeset without crashing the server", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", dir)

    # A missing description fails validation in the functional core.
    assert {:error, %Ecto.Changeset{}} = Tracking.add_expense(book.id, %{cost: "5.00"})

    # The server is still alive and holds no expense.
    assert BookServer.alive?(book.id)
    assert Tracking.list_expenses(book.id) == []
  end

  test "open_book/1 fails and starts no server for a readable but invalid .lcbook", %{
    tmp_dir: dir
  } do
    id = "bad00000-0000-4000-8000-000000000000"
    File.write!(Path.join(dir, id <> ".lcbook"), "garbage")

    assert {:error, {:invalid_document, ^id}} = Tracking.open_book(id, dir)
    refute BookServer.alive?(id)
  end

  test "close_book stops the server for good and it is not restarted", %{tmp_dir: dir} do
    # Regression guard: with the default :permanent restart, the DynamicSupervisor
    # would resurrect a just-closed BookServer (defeating close/1). :transient must
    # keep an intentional :normal close stopped.
    {:ok, book} = Tracking.create_book("Family", dir)
    [{pid, _}] = Registry.lookup(LocalCents.Tracking.BookRegistry, book.id)
    ref = Process.monitor(pid)

    :ok = Tracking.close_book(book.id)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    # Give the supervisor a beat; a :permanent restart would land almost immediately.
    Process.sleep(50)
    refute BookServer.alive?(book.id)
  end

  test "state persists across an explicit close and reopen", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", dir)
    {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

    assert BookServer.alive?(book.id)
    :ok = Tracking.close_book(book.id)
    refute BookServer.alive?(book.id)

    :ok = Tracking.open_book(book.id, dir)

    assert [%Tracking.Expense{description: "Coffee"}] = Tracking.list_expenses(book.id)
  end
end
