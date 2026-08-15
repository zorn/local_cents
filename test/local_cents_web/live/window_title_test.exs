defmodule LocalCentsWeb.WindowTitleTest do
  # async: false — `flip_link/1` broadcasts on the global `sync-link` topic, which the
  # universal `LocalCentsWeb.WindowTitle` hook subscribes every open window to. Run
  # asynchronously, an `:offline` flip here would bleed into other modules' live windows
  # and mark their titles mid-test. The topic is a single global link with no per-test
  # scope, so exclusive execution is how this test claims it.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.PeerClient

  @moduletag :tmp_dir

  setup :with_async_books_dir

  # Simulates the operator flipping the Mac-side offline toggle: `PeerClient` broadcasts
  # the same `{:sync_link, state}` on a user flip, which every open window is subscribed
  # to (see the Sync Demo, ADR 0025).
  defp flip_link(state) do
    Phoenix.PubSub.broadcast(LocalCents.PubSub, PeerClient.link_topic(), {:sync_link, state})
  end

  test "a book window's title gains and drops the offline marker with the link", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    session =
      conn
      |> visit(~p"/books/#{book.id}")
      |> refute_has("[data-tauri-drag-region]", text: "(Offline)")

    flip_link(:offline)
    assert_has(session, "[data-tauri-drag-region]", text: "Family Expenses (Offline)")

    flip_link(:online)

    session
    |> assert_has("[data-tauri-drag-region]", text: "Family Expenses")
    |> refute_has("[data-tauri-drag-region]", text: "(Offline)")
  end

  test "the library window follows the same offline rule", ~M{conn} do
    session =
      conn
      |> visit(~p"/library")
      |> refute_has("[data-tauri-drag-region]", text: "(Offline)")

    flip_link(:offline)
    assert_has(session, "[data-tauri-drag-region]", text: "Library (Offline)")

    flip_link(:online)

    session
    |> assert_has("[data-tauri-drag-region]", text: "Library")
    |> refute_has("[data-tauri-drag-region]", text: "(Offline)")
  end

  # No `PeerClient` runs in these tests, so `link_state/0` is `nil` — the solo, no-peer
  # case of normal use. The marker must never appear there.
  test "a solo app with no peer configured shows a plain title", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/books/#{book.id}")
    |> assert_has("[data-tauri-drag-region]", text: "Family Expenses")
    |> refute_has("[data-tauri-drag-region]", text: "(Offline)")
  end
end
