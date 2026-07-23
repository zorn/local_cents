defmodule LocalCentsWeb.BookLive do
  @moduledoc """
  A single open `Book`, mounted at `/books/:id` — the document view.

  On the desktop this LiveView is loaded into its own native window, one per `Book`
  (see [ADR 0006](0006-multi-window-desktop-shell.html)). It ensures the `Book`'s
  runtime process is running and subscribes to its change broadcasts so the list
  stays live as the `Book` is edited elsewhere.

  The window lists the Book's expenses (newest first) and offers two capture paths.
  A **quick-add** bar pinned at the top takes a single line — a trailing amount is
  the cost, the rest the description (see `LocalCents.Tracking.QuickAdd`) — and
  creates the expense on Enter, clearing the field for the next one. The **full
  editor** is a slide-in panel that adds, edits, and (behind a confirmation)
  hard-deletes an expense. The editor files an expense under a Category with a
  `<select>` over the Book's existing categories, committed by the same Save as the
  text fields (see [ADR 0018](0018-category-assignment-through-the-editor.html)); a
  blank selection leaves it Uncategorized. The picker's option list is a
  `@categories` cache refreshed only on the Book's `:categories_updated` broadcast,
  so ordinary expense edits never churn it.
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Expense
  alias LocalCentsWeb.DesktopShell

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    # `open_book/1` fails for an id with no `.lcbook` on disk; `get_book/1` still
    # returns nil if the file vanished between the two calls (a delete race). Both
    # mean "no Book to show here", so both fall through to the library redirect
    # and `@book` is only ever a real struct by the time `render/1` runs.
    with :ok <- Tracking.open_book(id),
         %Tracking.Book{} = book <- Tracking.get_book(id) do
      if connected?(socket), do: Tracking.subscribe(id)

      socket
      |> assign(book: book, page_title: book.name, editor: nil, confirm_delete: nil)
      |> assign(quick_add_line: "")
      |> assign(time_zone: connected_time_zone(socket), expenses: load_expenses(id))
      |> assign_categories(load_categories(id))
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
      <%!-- `relative` scopes the side-panel editor's `absolute inset-0` to this
      content area (below the native title bar), not the whole window; `h-full` pins
      the column so the list scrolls inside it and the action bar stays visible. --%>
      <div class="relative flex h-full flex-col overflow-hidden">
        <%!-- The title bar's book name is decorative chrome (aria-hidden); this
        heading carries the name for assistive tech and document structure. --%>
        <h1 class="sr-only">{@book.name}</h1>

        <%!-- Quick-add sits at the top so a long expense list never scrolls it out
        of reach. Enter creates the expense and clears the field for the next one;
        the trailing button opens the reliable full editor. --%>
        <form
          id="quick-add-form"
          phx-submit="quick_add"
          phx-change="quick_add_change"
          class="pt-4 pb-3"
        >
          <Bond.input_bar>
            <:leading_content>
              <%!-- The field shows only a placeholder; this sr-only label gives it an
              accessible name for assistive tech. --%>
              <label for="quick-add-input" class="sr-only">Quick add expense</label>
              <Bond.input
                id="quick-add-input"
                name="line"
                value={@quick_add_line}
                placeholder="coffee 4.75"
                class="flex-1"
                autocomplete="off"
              />
            </:leading_content>
            <:trailing_content>
              <Bond.button phx-click="new_expense">New Expense</Bond.button>
            </:trailing_content>
          </Bond.input_bar>
        </form>

        <div class="flex min-h-0 flex-1 flex-col">
          <Bond.empty_state
            :if={@expenses == []}
            message="No expenses yet"
            hint="Add one above to get started."
          />

          <div :if={@expenses != []} id="expenses" class="flex min-h-0 flex-1 flex-col">
            <Bond.list_view fill>
              <Bond.expense_cell
                :for={expense <- @expenses}
                id={"expense-#{expense.id}"}
                date_display={format_date(expense.date)}
                description={expense.description}
                amount_display={format_amount(expense.cost)}
                category={Map.get(@category_names, expense.category_id)}
                phx-click="edit_expense"
                phx-value-id={expense.id}
              />
            </Bond.list_view>
          </div>
        </div>

        <div class="flex items-center p-4">
          <Bond.button variant={:outline} phx-click="open_categories">Categories</Bond.button>
        </div>

        <Bond.side_panel
          :if={@editor}
          id="expense-editor"
          title={editor_title(@editor)}
          on_close="close_editor"
        >
          <.form
            for={@form}
            id="expense-form"
            phx-submit="save_expense"
            phx-change="validate_expense"
            class="space-y-3"
          >
            <Bond.input
              field={@form[:date]}
              type="date"
              label="Date"
              variant="frosted"
              class="w-full"
            />
            <Bond.input
              field={@form[:description]}
              label="Description"
              variant="frosted"
              class="w-full"
            />
            <Bond.input
              field={@form[:cost]}
              label="Cost"
              variant="frosted"
              class="w-full"
              placeholder="0.00"
            />
            <%!-- Filing is a plain form field (ADR 0018): a blank selection is
            Uncategorized. With no categories yet, the editor can't create one (that
            is the Categories view's job), so show a hint instead of a dead select. --%>
            <Bond.select
              :if={@categories != []}
              field={@form[:category_id]}
              label="Category"
              variant="frosted"
              class="w-full"
              options={category_options(@categories)}
            />
            <div :if={@categories == []}>
              <span class="text-xs font-semibold uppercase tracking-wide block mb-1 text-primary-400">
                Category
              </span>
              <p class="text-sm text-primary-400/80">
                No categories yet — add them from Categories.
              </p>
            </div>
            <div class="flex items-center justify-between pt-2">
              <%!-- Delete only exists for a saved expense; a spacer keeps Save pinned
              right when adding, since the row is justify-between. --%>
              <Bond.button
                :if={match?({:edit, _}, @editor)}
                type="button"
                variant={:destructive}
                phx-click="request_delete"
              >
                Delete
              </Bond.button>
              <span :if={match?({:new, _}, @editor)}></span>
              <Bond.button type="submit">{submit_label(@editor)}</Bond.button>
            </div>
          </.form>
        </Bond.side_panel>
      </div>

      <Bond.modal
        :if={@confirm_delete}
        id="delete-expense-modal"
        title="Delete Expense"
        on_cancel="cancel_delete"
      >
        <p class="text-sm text-surface-700">
          Delete <span class="font-semibold">{@confirm_delete.description}</span>? This permanently
          removes the expense and cannot be undone.
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
  def handle_event("open_categories", _params, socket) do
    # A Book's category management lives on its own page inside this same native
    # window (see [ADR 0017](0017-in-window-secondary-views.html)).
    socket
    |> push_navigate(to: ~p"/books/#{socket.assigns.book.id}/categories")
    |> noreply()
  end

  # Mirror the field into an assign so a successful submit can clear it (setting the
  # bound value back to "") — an uncontrolled input would keep the just-added text.
  def handle_event("quick_add_change", %{"line" => line}, socket) do
    socket
    |> assign(quick_add_line: line)
    |> noreply()
  end

  def handle_event("quick_add", %{"line" => line}, socket) do
    book = socket.assigns.book

    case Tracking.quick_add_expense(book.id, line, today: today(socket.assigns.time_zone)) do
      {:ok, _expense} ->
        # Reload now rather than wait for our own broadcast, matching the editor's
        # save path, and clear the field so the next line can be typed straight away.
        socket
        |> assign(quick_add_line: "", expenses: load_expenses(book.id))
        |> noreply()

      # A blank/whitespace line adds nothing and says nothing — the quiet no-op the
      # capture path is meant to have.
      {:error, :blank} ->
        noreply(socket)

      # The grammar can't actually produce an invalid Expense (a lone amount echoes
      # itself as the description), so this only guards an unexpected failure.
      {:error, _reason} ->
        failed(socket, "Could not add that expense.")
    end
  end

  def handle_event("new_expense", _params, socket) do
    # Seed a blank expense dated the user's local today so the field opens
    # pre-filled; a genuine save re-reads the field, so this default only shows.
    today = today(socket.assigns.time_zone)
    base = %Expense{date: today}

    socket
    |> assign(editor: {:new, base}, form: editor_form(base, today))
    |> noreply()
  end

  def handle_event("edit_expense", %{"id" => expense_id}, socket) do
    case find_expense(socket, expense_id) do
      %Expense{} = expense ->
        socket
        |> assign(
          editor: {:edit, expense},
          form: editor_form(expense, today(socket.assigns.time_zone))
        )
        |> noreply()

      nil ->
        # The row vanished (edited/deleted elsewhere); resync rather than open a
        # stale editor.
        socket
        |> assign(expenses: load_expenses(socket.assigns.book.id))
        |> noreply()
    end
  end

  # A concurrent `:book_updated` resync can close the editor before an in-flight
  # `phx-change`/`phx-submit`/delete event arrives; these events tolerate a nil
  # editor rather than crash the LiveView on a race.
  def handle_event("validate_expense", %{"expense" => expense_params}, socket) do
    case socket.assigns.editor do
      nil ->
        noreply(socket)

      editor ->
        base = editor_base(editor)

        socket
        |> assign(
          form: editor_form(base, today(socket.assigns.time_zone), expense_params, :validate)
        )
        |> noreply()
    end
  end

  def handle_event("save_expense", %{"expense" => expense_params}, socket) do
    save_expense(socket, socket.assigns.editor, expense_params)
  end

  def handle_event("close_editor", _params, socket) do
    socket
    |> assign(editor: nil, confirm_delete: nil)
    |> noreply()
  end

  def handle_event("request_delete", _params, socket) do
    case socket.assigns.editor do
      {:edit, expense} ->
        socket
        |> assign(confirm_delete: expense)
        |> noreply()

      _ ->
        noreply(socket)
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    socket
    |> assign(confirm_delete: nil)
    |> noreply()
  end

  def handle_event("confirm_delete", _params, socket) do
    case socket.assigns.confirm_delete do
      %Expense{} = expense -> delete_expense(socket, expense)
      nil -> noreply(socket)
    end
  end

  defp save_expense(socket, {:new, base}, expense_params) do
    book = socket.assigns.book
    today = today(socket.assigns.time_zone)

    case Tracking.add_expense(book.id, expense_params, today: today) do
      {:ok, _expense} -> saved(socket, book.id)
      {:error, %Ecto.Changeset{}} -> invalid(socket, base, expense_params, today)
      {:error, :category_not_found} -> category_gone(socket, base, expense_params, today)
      {:error, _reason} -> failed(socket, "Could not save the expense.")
    end
  end

  # An edit is a full replace of the existing expense's editable fields.
  defp save_expense(socket, {:edit, expense}, expense_params) do
    book = socket.assigns.book
    today = today(socket.assigns.time_zone)

    case Tracking.edit_expense(book.id, expense.id, expense_params, today: today) do
      {:ok, _expense} -> saved(socket, book.id)
      {:error, %Ecto.Changeset{}} -> invalid(socket, expense, expense_params, today)
      {:error, :not_found} -> saved(socket, book.id, "That expense no longer exists.")
      {:error, :category_not_found} -> category_gone(socket, expense, expense_params, today)
      {:error, _reason} -> failed(socket, "Could not save the expense.")
    end
  end

  defp save_expense(socket, nil, _expense_params), do: noreply(socket)

  defp delete_expense(socket, %Expense{} = expense) do
    book = socket.assigns.book

    case Tracking.delete_expense(book.id, expense.id) do
      :ok ->
        socket
        |> assign(editor: nil, confirm_delete: nil, expenses: load_expenses(book.id))
        |> noreply()

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Could not delete the expense.")
        |> assign(confirm_delete: nil)
        |> noreply()
    end
  end

  # Clear `confirm_delete` alongside the editor: if the delete-confirm modal were
  # open (via a race) when a save succeeds, leaving it set would strand the modal
  # after the editor closed.
  defp saved(socket, book_id, flash \\ nil) do
    socket
    |> maybe_flash(flash)
    |> assign(editor: nil, confirm_delete: nil, expenses: load_expenses(book_id))
    |> noreply()
  end

  defp maybe_flash(socket, nil), do: socket
  defp maybe_flash(socket, message), do: put_flash(socket, :info, message)

  # A submit that failed validation: rebuild the form from what the user typed so
  # their input survives and the changeset's errors surface (every field counts as
  # used on a submit, so `used_input?/1` lets them all show).
  defp invalid(socket, base, expense_params, today) do
    socket
    |> assign(form: editor_form(base, today, expense_params, :validate))
    |> noreply()
  end

  defp failed(socket, message) do
    socket
    |> put_flash(:error, message)
    |> noreply()
  end

  # The picked category was deleted between opening the editor and saving (the
  # `:category_not_found` backstop from ADR 0018). Refresh the cache, clear the now
  # dangling selection, and keep the user's other input so they can re-file and
  # retry rather than lose the edit.
  defp category_gone(socket, base, expense_params, today) do
    socket
    |> put_flash(:error, "That category no longer exists — it was cleared.")
    |> assign_categories(load_categories(socket.assigns.book.id))
    |> assign(form: blank_category_form(base, expense_params, today))
    |> noreply()
  end

  # Rebuild the editor form with the category selection cleared (Uncategorized) while
  # keeping the user's other input — the shared shape behind both the Save-time
  # backstop and the live vanished-selection reset (see ADR 0018).
  defp blank_category_form(base, params, today) do
    editor_form(base, today, Map.put(params, "category_id", ""), :validate)
  end

  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    case Tracking.get_book(id) do
      %Tracking.Book{} = book ->
        # `page_title` updates the document `<title>`, but the native window's
        # title bar does not follow it — push the new name to the shell too.
        DesktopShell.set_book_title(book)

        socket
        |> assign(book: book, page_title: book.name, expenses: load_expenses(id))
        |> close_editor_if_gone()
        |> noreply()

      nil ->
        socket
        |> redirect_missing("This book was deleted.")
        |> noreply()
    end
  end

  # The Book's category set changed (elsewhere or here). Refresh the picker's cache
  # only on this signal — not on the far more frequent `:book_updated` — so expense
  # edits don't churn the option list (see ADR 0018). If the open editor's selected
  # category was among those deleted, drop the selection to blank so the form and a
  # subsequent Save agree; the user's other in-progress input is preserved.
  def handle_info({:categories_updated, id}, socket) do
    socket
    |> assign_categories(load_categories(id))
    |> reset_selected_category_if_gone()
    |> noreply()
  end

  # A change elsewhere may have deleted the expense currently open in the editor;
  # drop the stale editor rather than let a Save/Delete act on a phantom.
  defp close_editor_if_gone(socket) do
    case socket.assigns.editor do
      {:edit, %Expense{id: id}} ->
        if Enum.any?(socket.assigns.expenses, &(&1.id == id)) do
          socket
        else
          assign(socket, editor: nil, confirm_delete: nil)
        end

      _ ->
        socket
    end
  end

  # The Book's process is running (mount ensured it), so `list_expenses/1` returns a
  # list; the `:not_open` clause is defensive for a mid-session close race.
  defp load_expenses(id) do
    case Tracking.list_expenses(id) do
      {:error, :not_open} -> []
      expenses -> Enum.sort_by(expenses, & &1.date, {:desc, Date})
    end
  end

  # Caches the sorted category list for the picker plus a `%{id => name}` map for
  # badge lookup, so rendering an expense row is a single `Map.get/2` rather than a
  # linear scan of the categories per row. Both derive from the same list, so they
  # are assigned together wherever categories are (re)loaded.
  defp assign_categories(socket, categories) do
    assign(socket,
      categories: categories,
      category_names: Map.new(categories, &{&1.id, &1.name})
    )
  end

  # Sorted by name so the picker (and any future category display) reads
  # alphabetically; the document's insertion order is not a display contract.
  defp load_categories(id) do
    case Tracking.list_categories(id) do
      {:error, :not_open} -> []
      categories -> Enum.sort_by(categories, & &1.name)
    end
  end

  # The `<select>` options as `{name, id}` pairs; a blank option (Uncategorized) is
  # supplied by `Bond.select` itself.
  defp category_options(categories), do: Enum.map(categories, &{&1.name, &1.id})

  # If the open editor's selected category was just deleted, clear it to blank so the
  # picker and a later Save agree. Rebuild from the form's current params so the
  # user's unsaved date/description/cost typing survives; only the category resets.
  defp reset_selected_category_if_gone(%{assigns: %{editor: nil}} = socket), do: socket

  defp reset_selected_category_if_gone(socket) do
    selected = socket.assigns.form[:category_id].value

    cond do
      not present?(selected) -> socket
      category_exists?(socket.assigns.categories, selected) -> socket
      true -> clear_selected_category(socket)
    end
  end

  defp clear_selected_category(socket) do
    base = editor_base(socket.assigns.editor)
    form = blank_category_form(base, socket.assigns.form.params, today(socket.assigns.time_zone))
    assign(socket, form: form)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp category_exists?(categories, id), do: Enum.any?(categories, &(&1.id == id))

  defp find_expense(socket, expense_id) do
    Enum.find(socket.assigns.expenses, &(&1.id == expense_id))
  end

  defp editor_base({_mode, %Expense{} = expense}), do: expense

  defp editor_title({:new, _base}), do: "New Expense"
  defp editor_title({:edit, _expense}), do: "Edit Expense"

  # "Create" for the new-expense form submit, "Save" for edits — the house UI
  # vocabulary (see docs/ui-language.md: "New" to initiate, "Create" to submit).
  defp submit_label({:new, _base}), do: "Create"
  defp submit_label({:edit, _expense}), do: "Save"

  # Builds the editor form from the Expense changeset (see ADR 0016 — Ecto for
  # validation, with `phoenix_ecto` supplying the form binding). The form action
  # is a UI concern, so it lives here at the call site rather than in the domain
  # changeset: a nil action (on open) hides errors, `:validate` surfaces them on
  # change and on a failed submit.
  defp editor_form(expense, today, params \\ %{}, action \\ nil) do
    expense
    |> Expense.changeset(params, today)
    |> to_form(action: action)
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%m/%d/%Y")

  # Cost is optional; a nil cost is an honest "needs amount", shown as an em dash
  # rather than a fake $0.00 (see ADR 0008). Currency formatting is minimal here —
  # a dedicated currency display arrives in a later ticket.
  defp format_amount(nil), do: "—"
  defp format_amount(%Decimal{} = cost), do: "$" <> Decimal.to_string(Decimal.round(cost, 2))

  # The IANA time zone the browser reported on connect (e.g. "America/New_York"),
  # falling back to UTC on the static first render (no connect params yet).
  defp connected_time_zone(socket) do
    case get_connect_params(socket) do
      %{"time_zone" => time_zone} when is_binary(time_zone) -> time_zone
      _ -> "Etc/UTC"
    end
  end

  # The user's *local* calendar date — the domain treats "today" as the user's
  # date, not the server's (see `LocalCents.Tracking`), so a blank date defaults
  # to the right day near midnight in any zone. Falls back to UTC on an unknown zone.
  defp today(time_zone) do
    case DateTime.now(time_zone) do
      {:ok, now} -> DateTime.to_date(now)
      {:error, _reason} -> Date.utc_today()
    end
  end

  defp redirect_missing(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/library")
  end
end
