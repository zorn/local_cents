defmodule LocalCentsWeb.ScopedBooksDirTest do
  @moduledoc """
  Guards the one claim the whole suite's `async: true` rests on: that a books
  directory claimed by a test process is the directory a LiveView mounted *by that
  test* writes to and reads from.

  Every feature test module depends on this working, but none of them says so: each
  would still pass if the directory resolved to the shared application-env default,
  right up until two of them ran at once. This module states the claim outright, so
  removing the seam in `LocalCents.ProcessConfig` fails here rather than showing up
  later as an unexplained cross-test collision.
  """

  use LocalCentsWeb.FeatureCase, async: true

  alias LocalCents.ProcessConfig
  alias LocalCents.Tracking

  @moduletag :tmp_dir

  setup ~M{tmp_dir} do
    ProcessConfig.put(:books_dir, tmp_dir)
    :ok
  end

  test "an ambient read in the test process resolves the claimed directory", ~M{tmp_dir} do
    # Guards against passing vacuously: the claimed directory has to be somewhere the
    # application env is *not* pointing, or this proves nothing.
    refute tmp_dir == Application.get_env(:local_cents, :books_dir)

    {:ok, _} = Tracking.create_book("Family Expenses")

    assert [%Tracking.Book{name: "Family Expenses"}] = Tracking.list_books()
    assert Path.wildcard(Path.join(tmp_dir, "*.lcbook")) != []
  end

  test "a LiveView mounted by the test resolves the same directory", ~M{conn, tmp_dir} do
    {:ok, _} = Tracking.create_book("Family Expenses")

    # The read direction: this render runs in the LiveView process, so a Book the
    # test process wrote is listed only if the view resolved the claim as well.
    session =
      conn
      |> visit(~p"/library")
      |> assert_has("#books", text: "Family Expenses")

    # The write direction, which the read does not prove on its own: `handle_event/3`
    # runs in the LiveView process, so creating a Book through the window is a write
    # issued from there rather than from the test.
    session
    |> click_button("New Book")
    |> fill_in("New book name", with: "Groceries")
    |> click_button("Create")
    |> assert_has("#books", text: "Groceries")

    # Both Books are on disk in the claimed directory — the second one could only
    # have landed here if the LiveView resolved it.
    assert length(Path.wildcard(Path.join(tmp_dir, "*.lcbook"))) == 2
  end
end
