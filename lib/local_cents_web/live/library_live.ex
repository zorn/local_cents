defmodule LocalCentsWeb.LibraryLive do
  @moduledoc """
  The library: lists every `Book`, creates new ones, and opens each in its own
  native window.

  Launching LocalCents opens this view in the persistent library window (see
  [ADR 0006](0006-multi-window-desktop-shell.html)). Creating a `Book` from the
  inline form both persists it and opens its document window; opening an existing
  `Book` asks the native shell — via `LocalCentsWeb.DesktopShell` — to open (or
  focus) a separate window at `/books/:id`, so several `Book`s can be open at once
  while the library window itself stays put.

  Each row carries an overflow menu for the per-Book actions that need
  confirmation or input: **Rename** (a modal name field) and **Delete** (a modal
  confirmation). Both changes propagate to an open document window — a rename
  updates its title live, and a delete closes it to the library with a notice —
  through `LocalCents.Tracking`'s broadcasts.
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCentsWeb.DesktopShell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(
      books: Tracking.list_books(),
      create_name: "",
      create_errors: [],
      open_menu_id: nil,
      dialog: nil,
      rename_errors: []
    )
    |> ok()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl p-4">
        <h1 class="mb-4 text-xl font-semibold text-surface-800">Library</h1>

        <form
          id="create-book-form"
          phx-submit="create"
          phx-change="validate_create"
          class="mb-6 flex items-end gap-2"
        >
          <Bond.input
            id="new-book-name"
            name="name"
            value={@create_name}
            label="New book name"
            errors={@create_errors}
            class="flex-1"
          />
          <Bond.button type="submit">Create</Bond.button>
        </form>

        <p
          :if={@books == []}
          class="rounded-lg border border-dashed border-surface-300 px-4 py-8 text-center text-sm text-surface-500"
        >
          No books yet — name one above to get started.
        </p>

        <div :if={@books != []} id="books">
          <Bond.list_view>
            <Bond.book_cell :for={book <- @books} id={"book-#{book.id}"} name={book.name}>
              <:actions>
                <div class="relative">
                  <Bond.button variant={:square} phx-click="toggle_menu" phx-value-id={book.id}>
                    <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
                    <span class="sr-only">Book actions</span>
                  </Bond.button>
                  <div
                    :if={@open_menu_id == book.id}
                    id={"menu-#{book.id}"}
                    phx-click-away="close_menu"
                    class="absolute right-0 top-full z-20 mt-1 min-w-[8rem] rounded-lg bg-surface-50 py-1 shadow-lg"
                    style="border: 1px solid var(--color-surface-300)"
                  >
                    <button
                      type="button"
                      phx-click="open_rename"
                      phx-value-id={book.id}
                      class="block w-full px-3 py-1.5 text-left text-sm text-surface-700 hover:bg-surface-100 transition-colors"
                    >
                      Rename
                    </button>
                    <button
                      type="button"
                      phx-click="open_delete"
                      phx-value-id={book.id}
                      class="block w-full px-3 py-1.5 text-left text-sm transition-colors hover:bg-surface-100"
                      style="color: var(--color-error-400)"
                    >
                      Delete
                    </button>
                  </div>
                </div>
                <Bond.button variant={:outline} phx-click="open" phx-value-id={book.id}>
                  Open
                </Bond.button>
              </:actions>
            </Bond.book_cell>
          </Bond.list_view>
        </div>
      </div>

      <Bond.modal
        :if={match?({:rename, _}, @dialog)}
        id="rename-modal"
        title="Rename Book"
        on_cancel="close_dialog"
      >
        <form id="rename-book-form" phx-submit="rename" class="space-y-4">
          <Bond.input
            id="rename-name"
            name="name"
            value={dialog_book(@dialog).name}
            label="New name"
            errors={@rename_errors}
            class="w-full"
          />
          <div class="flex items-center justify-end gap-2">
            <Bond.button type="button" variant={:outline} phx-click="close_dialog">
              Cancel
            </Bond.button>
            <Bond.button type="submit">Rename</Bond.button>
          </div>
        </form>
      </Bond.modal>

      <Bond.modal
        :if={match?({:delete, _}, @dialog)}
        id="delete-modal"
        title="Delete Book"
        on_cancel="close_dialog"
      >
        <p class="text-sm text-surface-700">
          Delete <span class="font-semibold">{dialog_book(@dialog).name}</span>? This permanently
          removes the book and cannot be undone.
        </p>
        <:actions>
          <Bond.button type="button" variant={:outline} phx-click="close_dialog">Cancel</Bond.button>
          <Bond.button type="button" phx-click="delete">Delete</Bond.button>
        </:actions>
      </Bond.modal>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("validate_create", %{"name" => name}, socket) do
    # Track the field so it can be cleared after a successful create, and drop a
    # standing "can't be blank" once the user has typed something (don't nag mid-edit).
    errors =
      case String.trim(name) do
        "" -> socket.assigns.create_errors
        _typed -> []
      end

    socket
    |> assign(create_name: name, create_errors: errors)
    |> noreply()
  end

  def handle_event("create", %{"name" => name}, socket) do
    case validate_name(name) do
      {:ok, trimmed} -> create_book(socket, trimmed)
      :error -> socket |> assign(create_errors: ["can't be blank"]) |> noreply()
    end
  end

  def handle_event("open", %{"id" => id}, socket) do
    with %Tracking.Book{} = book <- Tracking.get_book(id),
         :ok <- Tracking.open_book(book.id) do
      DesktopShell.open_book(book)
      noreply(socket)
    else
      nil ->
        # The book vanished (e.g. deleted in another window); resync the list.
        socket |> assign(books: Tracking.list_books()) |> noreply()

      {:error, _reason} ->
        socket |> put_flash(:error, "Could not open the book.") |> noreply()
    end
  end

  def handle_event("toggle_menu", %{"id" => id}, socket) do
    # Clicking the open row's toggle closes it; any other row's opens that one.
    socket |> assign(open_menu_id: toggle_menu_id(socket.assigns.open_menu_id, id)) |> noreply()
  end

  def handle_event("close_menu", _params, socket) do
    socket |> assign(open_menu_id: nil) |> noreply()
  end

  def handle_event("open_rename", %{"id" => id}, socket) do
    open_dialog(socket, :rename, id)
  end

  def handle_event("open_delete", %{"id" => id}, socket) do
    open_dialog(socket, :delete, id)
  end

  def handle_event("close_dialog", _params, socket) do
    socket |> assign(dialog: nil, rename_errors: []) |> noreply()
  end

  def handle_event("rename", %{"name" => name}, socket) do
    {:rename, book} = socket.assigns.dialog

    case validate_name(name) do
      {:ok, trimmed} ->
        case Tracking.rename_book(book.id, trimmed) do
          :ok -> socket |> resync_and_close_dialog() |> noreply()
          {:error, _reason} -> dismiss_dialog_with_error(socket, "Could not rename the book.")
        end

      :error ->
        socket |> assign(rename_errors: ["can't be blank"]) |> noreply()
    end
  end

  def handle_event("delete", _params, socket) do
    {:delete, book} = socket.assigns.dialog

    case Tracking.delete_book(book.id) do
      :ok -> socket |> resync_and_close_dialog() |> noreply()
      {:error, _reason} -> dismiss_dialog_with_error(socket, "Could not delete the book.")
    end
  end

  defp create_book(socket, name) do
    case Tracking.create_book(name) do
      {:ok, book} ->
        # Creating a book opens its document window straight away (ADR 0006).
        DesktopShell.open_book(book)

        socket
        |> assign(books: Tracking.list_books(), create_name: "", create_errors: [])
        |> noreply()

      {:error, _reason} ->
        socket |> put_flash(:error, "Could not create the book.") |> noreply()
    end
  end

  # Opens a per-Book action dialog, closing the overflow menu. Re-reads the Book so
  # the modal shows a fresh name and quietly resyncs if it was deleted meanwhile.
  defp open_dialog(socket, kind, id) do
    case Tracking.get_book(id) do
      %Tracking.Book{} = book ->
        socket |> assign(dialog: {kind, book}, open_menu_id: nil, rename_errors: []) |> noreply()

      nil ->
        socket |> assign(books: Tracking.list_books(), open_menu_id: nil) |> noreply()
    end
  end

  # A dialog change succeeded: pick up the new library state and close the dialog.
  defp resync_and_close_dialog(socket) do
    assign(socket, books: Tracking.list_books(), dialog: nil, rename_errors: [])
  end

  # A dialog change failed: surface the reason and close the dialog.
  defp dismiss_dialog_with_error(socket, message) do
    socket
    |> put_flash(:error, message)
    |> assign(dialog: nil, rename_errors: [])
    |> noreply()
  end

  defp toggle_menu_id(open_id, open_id), do: nil
  defp toggle_menu_id(_open_id, id), do: id

  defp dialog_book({_kind, book}), do: book

  defp validate_name(name) do
    case String.trim(name) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end
end
