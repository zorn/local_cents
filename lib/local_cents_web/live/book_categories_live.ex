defmodule LocalCentsWeb.BookCategoriesLive do
  @moduledoc """
  A single open `Book`'s category management view, mounted at
  `/books/:id/categories`.

  This is a secondary page of the Book's one native document window, reached by
  navigating from `LocalCentsWeb.BookLive` rather than by opening a second window
  (see [ADR 0017](0017-in-window-secondary-views.html)). It repeats that view's
  mount contract — ensure the Book's runtime process is running, then subscribe to
  its change broadcasts — so the category list and per-category expense counts stay
  live as the Book is edited elsewhere.

  Categories are the curated "hard list" a Book totals its spending by (see
  [ADR 0005](0005-categories-not-tags.html)). Here the user adds, renames (inline,
  GitHub-style), and deletes them. Deleting un-files the affected expenses to
  Uncategorized, behind a confirmation that names the consequence. The
  "Uncategorized" bucket itself is not shown here — it is not a Category and belongs
  to the group-by/totals view.
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Category
  alias LocalCentsWeb.DesktopShell

  @impl Phoenix.LiveView
  def mount(%{"id" => book_id}, _session, socket) do
    with :ok <- Tracking.open_book(book_id),
         %Tracking.Book{} = book <- Tracking.get_book(book_id) do
      if connected?(socket), do: Tracking.subscribe(book_id)

      socket
      |> assign(book: book, page_title: book.name, editing: nil, form: nil)
      |> assign(confirm_delete: nil, add_nonce: 0, categories: load_categories(book_id))
      |> ok()
    else
      _ ->
        socket
        |> redirect_missing("That book could not be found.")
        |> ok()
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} window_title={@book.name}>
      <div class="relative flex h-full flex-col overflow-hidden">
        <div class="flex items-center gap-3 border-b border-surface-200 px-4 py-3">
          <.link
            navigate={~p"/books/#{@book.id}"}
            class="inline-flex items-center gap-1 text-sm text-surface-600 transition-colors hover:text-primary-800"
          >
            <.icon name="hero-chevron-left" class="h-4 w-4" /> Expenses
          </.link>
          <h1 class="text-sm font-semibold text-surface-800">Categories</h1>
        </div>

        <div class="flex min-h-0 flex-1 flex-col">
          <Bond.empty_state
            :if={@categories == [] and @editing != :new}
            message="No categories yet"
            hint="Add one to start grouping your expenses."
          />

          <div
            :if={@categories != [] or @editing == :new}
            id="categories"
            class="flex min-h-0 flex-1 flex-col"
          >
            <Bond.list_view fill>
              <Bond.category_row
                :if={@editing == :new}
                id="category-row-new"
                editing
                input_id={"category-name-new-#{@add_nonce}"}
                form={@form}
                submit_label="Create"
                on_save="save_category"
                on_change="validate_category"
                on_cancel="cancel_edit"
              />
              <%= for category <- @categories do %>
                <%= if @editing == {:edit, category.id} do %>
                  <Bond.category_row
                    id={"category-row-#{category.id}"}
                    editing
                    input_id={"category-name-#{category.id}"}
                    form={@form}
                    on_save="save_category"
                    on_change="validate_category"
                    on_cancel="cancel_edit"
                  />
                <% else %>
                  <Bond.category_row
                    id={"category-row-#{category.id}"}
                    category_id={category.id}
                    name={category.name}
                    count_label={expense_count_label(category.count)}
                    on_edit="edit_category"
                    on_delete="request_delete"
                  />
                <% end %>
              <% end %>
            </Bond.list_view>
          </div>
        </div>

        <div class="p-4">
          <Bond.button phx-click="new_category">New Category</Bond.button>
        </div>
      </div>

      <Bond.modal
        :if={@confirm_delete}
        id="delete-category-modal"
        title={~s(Delete the "#{@confirm_delete.name}" category?)}
        on_cancel="cancel_delete"
      >
        <p class="text-sm text-surface-700">
          <%= if @confirm_delete.count == 0 do %>
            This can't be undone.
          <% else %>
            Its <span class="font-semibold">{expense_count_label(@confirm_delete.count)}</span>
            will become Uncategorized. You can re-file them later.
          <% end %>
        </p>
        <:actions>
          <Bond.button type="button" variant={:outline} phx-click="cancel_delete">Cancel</Bond.button>
          <Bond.button type="button" variant={:destructive} phx-click="confirm_delete">
            Delete
          </Bond.button>
        </:actions>
      </Bond.modal>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("new_category", _params, socket) do
    # Open a blank add row and bump the nonce so its input re-keys and autofocuses.
    socket
    |> assign(
      editing: :new,
      form: category_form(%Category{}),
      add_nonce: socket.assigns.add_nonce + 1
    )
    |> noreply()
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    case find_category(socket, id) do
      %{name: name} ->
        socket
        |> assign(editing: {:edit, id}, form: category_form(%Category{id: id, name: name}))
        |> noreply()

      nil ->
        # The row vanished (edited/deleted elsewhere); resync rather than open a
        # stale editor.
        socket
        |> assign(categories: load_categories(socket.assigns.book.id))
        |> noreply()
    end
  end

  def handle_event("save_category", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.editing, category_params)
  end

  # Live validation as the user types. It rebuilds the form with a `:validate`
  # action so errors can surface, but never commits — only Save (submit) does. A
  # nil editor is tolerated in case a resync cleared it mid-keystroke.
  def handle_event("validate_category", %{"category" => category_params}, socket) do
    case socket.assigns.editing do
      :new ->
        socket
        |> assign(form: category_form(%Category{}, category_params, :validate))
        |> noreply()

      {:edit, id} ->
        socket
        |> assign(form: category_form(%Category{id: id}, category_params, :validate))
        |> noreply()

      nil ->
        noreply(socket)
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    socket
    |> assign(editing: nil, form: nil)
    |> noreply()
  end

  def handle_event("request_delete", %{"id" => id}, socket) do
    case find_category(socket, id) do
      %{} = category ->
        socket
        |> assign(confirm_delete: category)
        |> noreply()

      nil ->
        socket
        |> assign(categories: load_categories(socket.assigns.book.id))
        |> noreply()
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    socket
    |> assign(confirm_delete: nil)
    |> noreply()
  end

  def handle_event("confirm_delete", _params, socket) do
    case socket.assigns.confirm_delete do
      %{id: id} -> delete_category(socket, id)
      nil -> noreply(socket)
    end
  end

  # A new category: keep the add row open with a fresh blank form and bump the
  # nonce so the input re-keys and refocuses, letting the user rattle off several.
  defp save_category(socket, :new, category_params) do
    book = socket.assigns.book

    case Tracking.add_category(book.id, category_params) do
      {:ok, _category} ->
        socket
        |> assign(
          form: category_form(%Category{}),
          add_nonce: socket.assigns.add_nonce + 1,
          categories: load_categories(book.id)
        )
        |> noreply()

      {:error, %Ecto.Changeset{}} ->
        socket
        |> assign(form: category_form(%Category{}, category_params, :validate))
        |> noreply()

      {:error, _reason} ->
        failed(socket, "Could not add the category.")
    end
  end

  defp save_category(socket, {:edit, id}, category_params) do
    book = socket.assigns.book

    case Tracking.rename_category(book.id, id, category_params) do
      {:ok, _category} ->
        socket
        |> assign(editing: nil, form: nil, categories: load_categories(book.id))
        |> noreply()

      {:error, %Ecto.Changeset{}} ->
        socket
        |> assign(form: category_form(%Category{id: id}, category_params, :validate))
        |> noreply()

      {:error, :not_found} ->
        socket
        |> put_flash(:info, "That category no longer exists.")
        |> assign(editing: nil, form: nil, categories: load_categories(book.id))
        |> noreply()

      {:error, _reason} ->
        failed(socket, "Could not rename the category.")
    end
  end

  # A concurrent `:book_updated` resync can clear `editing` before an in-flight
  # save arrives; tolerate a nil editor rather than crash.
  defp save_category(socket, nil, _category_params), do: noreply(socket)

  defp delete_category(socket, id) do
    book = socket.assigns.book

    case Tracking.delete_category(book.id, id) do
      :ok ->
        socket
        |> assign(confirm_delete: nil, categories: load_categories(book.id))
        |> clear_editing_if_gone()
        |> noreply()

      {:error, :not_found} ->
        socket
        |> put_flash(:info, "That category no longer exists.")
        |> assign(confirm_delete: nil, categories: load_categories(book.id))
        |> clear_editing_if_gone()
        |> noreply()

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Could not delete the category.")
        |> assign(confirm_delete: nil)
        |> noreply()
    end
  end

  defp failed(socket, message) do
    socket
    |> put_flash(:error, message)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    case Tracking.get_book(id) do
      %Tracking.Book{} = book ->
        # `page_title` updates the document `<title>`; the native title bar does not
        # follow it, so push the (possibly renamed) name to the shell too, matching
        # `BookLive`.
        DesktopShell.set_book_title(book)

        socket
        |> assign(book: book, page_title: book.name, categories: load_categories(id))
        |> clear_editing_if_gone()
        |> clear_confirm_if_gone()
        |> noreply()

      nil ->
        socket
        |> redirect_missing("This book was deleted.")
        |> noreply()
    end
  end

  # A change elsewhere may have deleted the category currently open for rename;
  # drop the stale editor rather than let a Save act on a phantom. An open add row
  # (`:new`) has no target, so it is left alone.
  defp clear_editing_if_gone(socket) do
    case socket.assigns.editing do
      {:edit, id} ->
        case Enum.any?(socket.assigns.categories, &(&1.id == id)) do
          true -> socket
          false -> assign(socket, editing: nil, form: nil)
        end

      _ ->
        socket
    end
  end

  # The category queued for deletion may have vanished elsewhere; drop the stale
  # confirmation so its modal doesn't strand.
  defp clear_confirm_if_gone(socket) do
    case socket.assigns.confirm_delete do
      %{id: id} ->
        case Enum.any?(socket.assigns.categories, &(&1.id == id)) do
          true -> socket
          false -> assign(socket, confirm_delete: nil)
        end

      nil ->
        socket
    end
  end

  # The Book's process is running (mount ensured it); the `:not_open` clauses are
  # defensive for a mid-session close race. Categories are shown alphabetically
  # (their stored order is not a stable contract), each paired with a count of the
  # expenses filed under it — derived here rather than via a context call.
  defp load_categories(id) do
    counts = expense_counts(id)

    case Tracking.list_categories(id) do
      {:error, :not_open} ->
        []

      categories ->
        categories
        |> Enum.map(fn category ->
          %{id: category.id, name: category.name, count: Map.get(counts, category.id, 0)}
        end)
        |> Enum.sort_by(&String.downcase(&1.name))
    end
  end

  defp expense_counts(id) do
    case Tracking.list_expenses(id) do
      {:error, :not_open} -> %{}
      expenses -> Enum.frequencies_by(expenses, & &1.category_id)
    end
  end

  defp find_category(socket, id) do
    Enum.find(socket.assigns.categories, &(&1.id == id))
  end

  # Builds the name form (see ADR 0016 — Ecto for validation). A nil action (on
  # open) hides errors; `:validate` surfaces them after a failed submit.
  defp category_form(category, params \\ %{}, action \\ nil) do
    category
    |> Category.changeset(params)
    |> to_form(action: action)
  end

  # The one place expense tallies become user-facing text — shared by the category
  # rows and the delete-confirmation body. Zero reads as an honest "None" rather
  # than "0 expenses"; one is singular.
  defp expense_count_label(0), do: "No expenses"
  defp expense_count_label(1), do: "1 expense"
  defp expense_count_label(count), do: "#{count} expenses"

  defp redirect_missing(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/library")
  end
end
