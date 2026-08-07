defmodule LocalCentsWeb.BookWindowTest do
  @moduledoc """
  Proves the `LocalCentsWeb.BookWindow` `on_mount` hook actually wires viewer
  registration end to end — that a real, connected document window counts as a viewer
  and that closing it lets the Book's runtime auto-shut-down. The pure runtime
  behavior is covered in `LocalCents.Tracking.BookServerShutdownTest`; this guards the
  web-side seam the fake-viewer tests can't reach.
  """

  use LocalCentsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LocalCents.BooksDirHelper
  import LocalCents.Eventually

  alias LocalCents.Tracking
  alias LocalCents.Tracking.BookServer
  alias LocalCents.Tracking.Presence

  @moduletag :tmp_dir

  setup :with_async_books_dir

  test "a connected document window registers a viewer and reaps on disconnect", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    [{server, _}] = Registry.lookup(LocalCents.Tracking.BookRegistry, book.id)
    ref = Process.monitor(server)

    {:ok, view, _html} = live(conn, ~p"/books/#{book.id}")

    # The hook ran `register_viewer/1` on connected mount, so this window is now a
    # tracked viewer of the Book.
    topic = BookServer.presence_topic(book.id)
    wait_until(fn -> map_size(Presence.list(topic)) == 1 end)

    # Closing the window (the LiveView process terminating) drops the viewer; with no
    # viewer left, the server persists once more and stops after the grace period.
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000
  end
end
