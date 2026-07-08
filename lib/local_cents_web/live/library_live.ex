defmodule LocalCentsWeb.LibraryLive do
  @moduledoc """
  The library: lists every `Book` and opens each in its own native window.

  Launching LocalCents opens this view in the persistent library window (see
  [ADR 0006](0006-multi-window-desktop-shell.html)). Opening a `Book` asks the
  native shell — via `LocalCentsWeb.DesktopShell` — to open (or focus) a separate
  document window at `/books/:id`; the library window itself stays put, so
  several `Book`s can be open at once.

  This is the interim shell needed to exercise multi-window behavior; the polished
  library UI lands with [issue #61](https://github.com/zorn/local_cents/issues/61).
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCentsWeb.DesktopShell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, books: Tracking.list_books())}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl p-4">
        <h1 class="mb-4 text-xl font-semibold">Library</h1>

        <form phx-submit="create" class="mb-6 flex items-end gap-2">
          <div class="flex-1">
            <.input type="text" name="name" value="" label="New book name" />
          </div>
          <.button>Create</.button>
        </form>

        <ul id="books" class="divide-y divide-gray-200 dark:divide-gray-700">
          <li
            :for={book <- @books}
            id={"book-#{book.id}"}
            class="flex items-center justify-between py-3"
          >
            <span>{book.name}</span>
            <.button phx-click="open" phx-value-id={book.id}>Open</.button>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("create", %{"name" => name}, socket) do
    case name |> String.trim() |> create_book() do
      {:ok, _book} ->
        {:noreply, assign(socket, books: Tracking.list_books())}

      :empty ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not create the book.")}
    end
  end

  def handle_event("open", %{"id" => id}, socket) do
    with %Tracking.Book{} = book <- Enum.find(socket.assigns.books, &(&1.id == id)),
         :ok <- Tracking.open_book(book.id) do
      DesktopShell.open_book(book)
      {:noreply, socket}
    else
      nil -> {:noreply, socket}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Could not open the book.")}
    end
  end

  defp create_book(""), do: :empty
  defp create_book(name), do: Tracking.create_book(name)
end
