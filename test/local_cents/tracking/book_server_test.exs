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
