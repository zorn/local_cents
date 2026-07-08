defmodule LocalCentsWeb.DesktopShell do
  @moduledoc """
  Requests native windows from the Tauri shell over the `ElixirKit.PubSub` bridge.

  LocalCents is a multi-window desktop app (see
  [ADR 0006](0006-multi-window-desktop-shell.html)): Elixir drives native window
  creation by *publishing* a command; Rust's subscriber opens (or focuses) the
  window. This module is the single place that builds those command payloads, so
  LiveViews never hand-assemble the wire format — the same discipline the
  `Phoenix.PubSub` topic scheme keeps for the in-app bus
  ([ADR 0011](0011-pubsub-topic-naming.html)).

  A command is JSON on the shared `"messages"` channel. `open-window` carries the
  window `label` (Rust's per-resource tag — re-requesting a label focuses the
  existing window rather than duplicating it), the LiveView `path` to load, and
  the native window `title`.
  """

  # Not a boundary of its own: this is part of the web layer, which already
  # depends on the tracking context for the `Book` type and reaches the
  # `ElixirKit.PubSub` bridge exactly as `LocalCentsWeb.HomeLive` does.
  alias LocalCents.Tracking.Book

  # The one duplex channel to the native shell. Fixed on both sides; see the
  # `ElixirKit.PubSub` bridge notes in `CLAUDE.md` and ADR 0011's final section.
  @channel "messages"

  @doc """
  Asks the native shell to open (or focus) the document window for `book`.

  Fire-and-forget: the broadcast is a no-op when no native shell is connected
  (dev via `mix phx.server`, tests), so this is safe to call from any LiveView.
  """
  @spec open_book(Book.t()) :: :ok
  def open_book(%Book{} = book) do
    ElixirKit.PubSub.broadcast(@channel, open_book_command(book))
  end

  @doc """
  Builds the JSON `open-window` command for `book`'s document window.

  The Book id is carried verbatim in both the window `label` (`"book-<id>"`, the
  tag Rust keys on to enforce one window per Book) and the `path`
  (`"/books/<id>"`). Split out from `open_book/1` so the wire format is unit
  testable without a live bridge.
  """
  @spec open_book_command(Book.t()) :: String.t()
  def open_book_command(%Book{id: id, name: name}) do
    Jason.encode!(%{
      action: "open-window",
      label: "book-" <> id,
      path: "/books/" <> id,
      title: name
    })
  end
end
