defmodule LocalCentsWeb.BookLive do
  @moduledoc """
  A single open `Book`, mounted at `/books/:id` — the document view.

  On the desktop this LiveView is loaded into its own native window, one per `Book`
  (see [ADR 0006](0006-multi-window-desktop-shell.html)). It ensures the `Book`'s
  runtime process is running and subscribes to its change broadcasts so the view
  stays live as the `Book` is edited elsewhere.

  This is the interim document shell; the expense list and editor arrive with
  [issue #63](https://github.com/zorn/local_cents/issues/63).
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    # `open_book/1` fails for an id with no `.lcbook` on disk; `get_book/1` still
    # returns nil if the file vanished between the two calls (a delete race). Both
    # mean "no Book to show here", so both fall through to the library redirect
    # and `@book` is only ever a real struct by the time `render/1` runs.
    with :ok <- Tracking.open_book(id),
         %Tracking.Book{} = book <- Tracking.get_book(id) do
      if connected?(socket), do: Tracking.subscribe(id)
      {:ok, assign(socket, book: book, page_title: book.name)}
    else
      _ -> {:ok, redirect_missing(socket, "That book could not be found.")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl p-4">
        <h1 class="text-xl font-semibold">{@book.name}</h1>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Expenses arrive in a later ticket.
        </p>
      </div>
    </Layouts.app>
    """
  end

  # Re-read the Book's identity on change so a rename reflects in the title. A
  # broadcast can also announce a deletion, in which case the Book is gone and the
  # window closes to the library with a notice (ADR 0006).
  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    case Tracking.get_book(id) do
      %Tracking.Book{} = book ->
        {:noreply, assign(socket, book: book, page_title: book.name)}

      nil ->
        {:noreply, redirect_missing(socket, "This book was deleted.")}
    end
  end

  defp redirect_missing(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/library")
  end
end
