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
    case Tracking.open_book(id) do
      :ok ->
        if connected?(socket), do: Tracking.subscribe(id)
        book = Tracking.get_book(id)
        {:ok, assign(socket, book: book, page_title: book_title(book))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "That book could not be found.")
         |> push_navigate(to: ~p"/library")}
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

  # Re-read the Book's identity on change so a rename reflects in the title.
  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    book = Tracking.get_book(id)
    {:noreply, assign(socket, book: book, page_title: book_title(book))}
  end

  defp book_title(nil), do: "LocalCents"
  defp book_title(%Tracking.Book{name: name}), do: name
end
