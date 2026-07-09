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

  New books are created from a bar pinned to the bottom of the window: a **New
  Book** button reveals an inline name field. Each row carries an overflow menu
  for the per-Book actions that need confirmation or input: **Rename** (a modal
  name field) and **Delete** (a modal confirmation). Renaming a Book updates its
  open document window's title live; deleting one asks the native shell to close
  that window up front (`LocalCentsWeb.DesktopShell.close_book/1`) — both via
  `LocalCents.Tracking`'s broadcasts and the window bridge.
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCentsWeb.DesktopShell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(
      books: Tracking.list_books(),
      creating: false,
      create_name: "",
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
      <%!-- h-screen (not min-h-screen) pins the column to the viewport so the list
      scrolls inside it and the bottom bar stays visible no matter how many books. --%>
      <div class="flex h-screen flex-col overflow-hidden">
        <%!-- The window's native title bar shows "Library"; this heading is for
        assistive tech and document structure. --%>
        <h1 class="sr-only">Library</h1>
        <div class="flex min-h-0 flex-1 flex-col">
          <p
            :if={@books == []}
            class="m-4 rounded-lg border border-dashed border-surface-400 px-4 py-10 text-center text-sm text-surface-600"
          >
            No books yet — add one below to get started.
          </p>

          <div :if={@books != []} id="books" class="flex min-h-0 flex-1 flex-col">
            <Bond.list_view fill>
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

        <div class="p-4">
          <form
            :if={@creating}
            id="create-book-form"
            phx-submit="create"
            phx-change="validate_create"
          >
            <Bond.input_bar>
              <:leading_content>
                <label for="new-book-name" class="sr-only">New book name</label>
                <Bond.input
                  id="new-book-name"
                  name="name"
                  value={@create_name}
                  placeholder="Name your new book"
                  class="min-w-0 flex-1"
                  phx-mounted={JS.focus()}
                />
              </:leading_content>
              <:trailing_content>
                <Bond.button type="button" variant={:outline} phx-click="cancel_create">
                  Cancel
                </Bond.button>
                <%!-- Disable rather than validate-on-submit: a blank name can't be
                submitted, so there's no error state to show or lay out. --%>
                <Bond.button type="submit" disabled={blank_name?(@create_name)}>
                  Create
                </Bond.button>
              </:trailing_content>
            </Bond.input_bar>
          </form>

          <div :if={!@creating}>
            <Bond.button phx-click="start_create">New Book</Bond.button>
          </div>
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
    # Track the field live so the Create button's disabled state follows it.
    socket |> assign(create_name: name) |> noreply()
  end

  def handle_event("start_create", _params, socket) do
    socket |> assign(creating: true, create_name: "") |> noreply()
  end

  def handle_event("cancel_create", _params, socket) do
    socket |> assign(creating: false, create_name: "") |> noreply()
  end

  def handle_event("create", %{"name" => name}, socket) do
    # Create is disabled while blank, so this only fires with a real name; the
    # guard just keeps a stray submit (e.g. Enter in an empty field) a no-op.
    case validate_name(name) do
      {:ok, trimmed} -> create_book(socket, trimmed)
      :error -> noreply(socket)
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

    # Close the Book's document window up front, then remove it, so the window
    # disappears on confirm rather than lingering to redirect itself (ADR 0006).
    DesktopShell.close_book(book)

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
        |> assign(books: Tracking.list_books(), creating: false, create_name: "")
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

  defp blank_name?(name), do: String.trim(name) == ""
end
