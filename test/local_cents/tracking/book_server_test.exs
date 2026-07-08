defmodule LocalCents.Tracking.BookServerTest do
  # Not async: uses a temporary books directory via the global :books_dir env.
  use ExUnit.Case, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking
  alias LocalCents.Tracking.BookServer

  setup :with_temp_books_dir

  test "a command broadcasts {:book_updated, id} to subscribers" do
    {:ok, book} = Tracking.create_book("Family")
    :ok = Tracking.subscribe(book.id)

    :ok = Tracking.add_expense(book.id, %Tracking.Expense{description: "Coffee", amount: 500})

    assert_receive {:book_updated, id}
    assert id == book.id
  end

  test "a failed persist returns an error, keeps state, and does not broadcast", %{books_dir: dir} do
    {:ok, book} = Tracking.create_book("Family")
    :ok = Tracking.subscribe(book.id)

    # Make the books directory read-only so the atomic write (temp file + rename)
    # cannot create its temp file (non-root).
    File.chmod!(dir, 0o555)

    assert {:error, _reason} =
             Tracking.add_expense(book.id, %Tracking.Expense{description: "Coffee", amount: 500})

    # Restore write access so the temp-dir cleanup can remove the directory.
    File.chmod!(dir, 0o755)

    # Persist-then-commit: the in-memory document was not updated, no broadcast fired,
    # and the server stayed alive rather than crashing and losing the change.
    refute_receive {:book_updated, _}
    assert Tracking.list_expenses(book.id) == []
    assert BookServer.alive?(book.id)
  end

  test "a command with an out-of-range amount errors without crashing the server" do
    {:ok, book} = Tracking.create_book("Family")
    over_i64 = 9_223_372_036_854_775_807 + 1

    assert {:error, _reason} =
             Tracking.add_expense(book.id, %Tracking.Expense{
               description: "Over",
               amount: over_i64
             })

    # The badarg was caught: the server is still alive and holds no expense.
    assert BookServer.alive?(book.id)
    assert Tracking.list_expenses(book.id) == []
  end

  test "open_book/1 fails and starts no server for a readable but invalid .lcbook", %{
    books_dir: dir
  } do
    id = "bad00000-0000-4000-8000-000000000000"
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, id <> ".lcbook"), "garbage")

    assert {:error, {:invalid_document, ^id}} = Tracking.open_book(id)
    refute BookServer.alive?(id)
  end

  test "close_book stops the server for good and it is not restarted" do
    # Regression guard: with the default :permanent restart, the DynamicSupervisor
    # would resurrect a just-closed BookServer (defeating close/1). :transient must
    # keep an intentional :normal close stopped.
    {:ok, book} = Tracking.create_book("Family")
    [{pid, _}] = Registry.lookup(LocalCents.Tracking.BookRegistry, book.id)
    ref = Process.monitor(pid)

    :ok = Tracking.close_book(book.id)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    # Give the supervisor a beat; a :permanent restart would land almost immediately.
    Process.sleep(50)
    refute BookServer.alive?(book.id)
  end

  test "state persists across an explicit close and reopen" do
    {:ok, book} = Tracking.create_book("Family")
    :ok = Tracking.add_expense(book.id, %Tracking.Expense{description: "Coffee", amount: 500})

    assert BookServer.alive?(book.id)
    :ok = Tracking.close_book(book.id)
    refute BookServer.alive?(book.id)

    :ok = Tracking.open_book(book.id)

    assert [%Tracking.Expense{description: "Coffee", amount: 500}] =
             Tracking.list_expenses(book.id)
  end
end
