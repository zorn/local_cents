defmodule LocalCentsWeb.BookWindow do
  @moduledoc """
  The shared `on_mount` hook for a Book's document-window views — the expenses list
  (`LocalCentsWeb.BookLive`), category management, and the Report — attached by each
  view in its own module, so the dependency is visible where it is relied on.

  Every such page repeats the same mount contract (see
  [ADR 0017](0017-in-window-secondary-views.html)): ensure the Book's runtime is
  running, redirect to the library if the Book is gone, and — once connected — both
  *subscribe* to its change broadcasts and *register as a viewer* so the runtime stays
  resident while the window is open and auto-shuts-down when it closes (see
  [ADR 0007](0007-book-runtime-and-persistence.html) and
  `docs/book-runtime-lifecycle.md`). Centralizing it here keeps the three views from
  drifting on that contract — a page that forgot to `register_viewer/1` would silently
  never keep its Book resident.

  The hook assigns `:book` and `:page_title`; each view reads `@book` and loads its own
  data. It reads the Book id from the `:book_id` route param, uniform across all three
  routes.

  Attach it with `on_mount LocalCentsWeb.BookWindow` under the view's `use` line, and
  match the assign in the mount head (`%{assigns: %{book: %Book{}}} = socket`) so the
  contract is stated in the signature. Do **not** also attach it in the router: hooks
  from the `live_session` and the module are additive, and the second `register_viewer/1`
  would fail as an already-tracked presence. `LocalCentsWeb.BookWindowAttachmentTest`
  fails the build if a routed document-window view omits the hook.
  """

  use LocalCentsWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_navigate: 2, put_flash: 3]

  alias LocalCents.Tracking
  alias Phoenix.LiveView.Socket

  require Logger

  @spec on_mount(:default, params :: map(), session :: map(), Socket.t()) ::
          {:cont, Socket.t()} | {:halt, Socket.t()}
  def on_mount(:default, %{"book_id" => book_id}, _session, socket) do
    # `open_book/1` fails for an id with no `.lcbook`; the follow-up read still comes
    # back empty if the file vanished between the two calls (a delete race). Both mean
    # "no Book here", so both redirect and `@book` is only ever a real struct once a
    # view renders.
    with :ok <- Tracking.open_book(book_id),
         %Tracking.Book{} = book <- fetch_book(socket, book_id) do
      {:cont, assign(socket, book: book, page_title: book.name)}
    else
      _ ->
        socket =
          socket
          |> put_flash(:error, "That book could not be found.")
          |> push_navigate(to: ~p"/library")

        {:halt, socket}
    end
  end

  # The connected mount both registers the viewer and gets the Book back from the
  # runtime's in-memory document, so there is no second disk read and no gap in which
  # the file could be deleted. The disconnected mount only renders the dead first
  # paint, so it reads from disk and registers nothing.
  defp fetch_book(socket, book_id) do
    if connected?(socket) do
      Tracking.subscribe(book_id)
      register_viewer(book_id)
    else
      Tracking.get_book(book_id)
    end
  end

  # Registering the viewer is what keeps the Book resident while its window is open, so
  # a failure here silently forfeits the lifecycle guarantee (the BookServer could reap
  # under an open window). It shouldn't block the mount — a failed track is far less
  # disruptive than refusing to render — so we log it and fall back to the disk read
  # rather than redirecting a window whose Book is perfectly readable.
  defp register_viewer(book_id) do
    case Tracking.register_viewer(book_id) do
      {:ok, %Tracking.Book{} = book} ->
        book

      {:error, reason} ->
        Logger.error("Failed to register viewer for book #{book_id}: #{inspect(reason)}")
        Tracking.get_book(book_id)
    end
  end
end
