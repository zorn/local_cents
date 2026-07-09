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
  the native window `title`. `close-window` carries only the `label` of the
  window to close. `set-title` carries the `label` and a new `title` for an
  already-open window (the native title bar does not follow the webview's
  document `<title>`, so a live rename must push it).
  """

  alias LocalCents.Tracking.Book

  # The one duplex channel to the native shell. Fixed on both sides; see the
  # `ElixirKit.PubSub` bridge notes in `CLAUDE.md` and ADR 0011's final section.
  @channel "messages"

  @doc "Asks the native shell to open (or focus) the document window for `book`."
  @spec open_book(Book.t()) :: :ok
  def open_book(%Book{} = book) do
    # Fire-and-forget: a no-op when no native shell is connected (dev via
    # `mix phx.server`, tests), so this is safe to call from any LiveView.
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

  @doc """
  Asks the native shell to close `book`'s document window.

  Used when a Book is deleted from the library: the open window is closed up
  front rather than left to redirect itself. Like `open_book/1`, this is
  fire-and-forget — a no-op when no native shell is connected (dev, tests) and
  harmless when the Book has no open window (Rust ignores an unknown label).
  """
  @spec close_book(Book.t()) :: :ok
  def close_book(%Book{} = book) do
    ElixirKit.PubSub.broadcast(@channel, close_book_command(book))
  end

  @doc """
  Builds the JSON `close-window` command for `book`'s document window.

  Carries only the window `label` (`"book-<id>"`) — the same tag `open_book/1`
  keyed the window on. Split out from `close_book/1` so the wire format is unit
  testable without a live bridge.
  """
  @spec close_book_command(Book.t()) :: String.t()
  def close_book_command(%Book{id: id}) do
    Jason.encode!(%{action: "close-window", label: "book-" <> id})
  end

  @doc """
  Asks the native shell to update `book`'s document window title to its current
  name.

  A renamed Book updates its LiveView (the in-page heading and the document
  `<title>`), but the native window's title bar was set once when Rust built the
  window and does not follow the webview — so a live rename must push the new
  title here. Fire-and-forget like the other commands.
  """
  @spec set_book_title(Book.t()) :: :ok
  def set_book_title(%Book{} = book) do
    ElixirKit.PubSub.broadcast(@channel, set_title_command(book))
  end

  @doc """
  Builds the JSON `set-title` command for `book`'s document window.

  Carries the window `label` (`"book-<id>"`) and the new `title`. Split out from
  `set_book_title/1` so the wire format is unit testable without a live bridge.
  """
  @spec set_title_command(Book.t()) :: String.t()
  def set_title_command(%Book{id: id, name: name}) do
    Jason.encode!(%{action: "set-title", label: "book-" <> id, title: name})
  end
end
