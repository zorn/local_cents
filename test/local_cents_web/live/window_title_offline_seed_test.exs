defmodule LocalCentsWeb.WindowTitleOfflineSeedTest do
  # async: false — this drives the real `PeerClient`, a named singleton, so two of these
  # must not run at once (the same reason the transport tests are synchronous).
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.PeerClient

  @moduletag :tmp_dir

  setup :with_async_books_dir

  # Suspending broadcasts `{:sync_link, :offline}`, but it fires before the window
  # mounts and subscribes, so no flip reaches it — the marker must come from the
  # mount-time seed alone.
  test "a window opened while already offline shows the marker immediately", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    start_supervised!(
      {PeerClient, uri: "ws://localhost:4001/peer/websocket", book_id: book.id, test_mode?: true}
    )

    :ok = PeerClient.suspend()
    assert PeerClient.link_state() == :offline

    conn
    |> visit(~p"/books/#{book.id}")
    |> assert_has("[data-tauri-drag-region]", text: "Family Expenses (Offline)")
  end
end
