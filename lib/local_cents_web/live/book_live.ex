defmodule LocalCentsWeb.BookLive do
  @moduledoc """
  A single open `Book`, mounted at `/books/:book_id` — the document view.

  On the desktop this LiveView is loaded into its own native window, one per `Book`
  (see [ADR 0006](0006-multi-window-desktop-shell.html)); driven from a browser it is a
  page, and the title bar gains a link back to the library since there is no window to
  close (see [ADR 0023](0023-browser-as-a-second-client.html)). Its mount contract comes
  from `LocalCentsWeb.BookWindow`, so the list stays live as the `Book` is edited
  elsewhere.

  The window lists the Book's expenses (newest first) and offers two capture paths.
  A **quick-add** bar pinned at the top takes a single line — a trailing amount is
  the cost, the rest the description (see `LocalCents.Tracking.QuickAdd`) — and
  creates the expense on Enter, clearing the field for the next one. The **full
  editor** is a slide-in panel that adds, edits, and (behind a confirmation)
  hard-deletes an expense; its render and save/validate/conflict logic live in
  `LocalCentsWeb.BookLive.Editor`, while this view keeps the expense list, the
  conflict signal, and the delete confirmation. The editor files an expense under a
  Category with a `<select>` over the Book's existing categories, committed by the same
  Save as the text fields (see [ADR 0018](0018-category-assignment-through-the-editor.html));
  a blank selection leaves it Uncategorized. The picker's option list is a
  `@categories` cache refreshed only on the Book's `:categories_updated` broadcast,
  so ordinary expense edits never churn it.
  """
  use LocalCentsWeb, :live_view

  on_mount LocalCentsWeb.BookWindow

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.Expense
  alias LocalCentsWeb.BookLive.Editor
  alias LocalCentsWeb.BookLive.Formatting
  alias LocalCentsWeb.DesktopShell
  alias Phoenix.LiveView.Socket

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{book: %Book{id: id}}} = socket) do
    socket
    |> assign(
      editor: nil,
      editor_tab: :details,
      confirm_delete: nil,
      quick_add_line: "",
      synced_changes_open: false
    )
    |> assign(time_zone: connected_time_zone(socket), expenses: load_expenses(id))
    |> assign_conflicts(id)
    |> assign_categories(load_categories(id))
    |> ok()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} client={@client} window_title={@page_title} back_path={~p"/library"}>
      <%!-- `relative` scopes the side-panel editor's `absolute inset-0` to this
      content area (below the native title bar), not the whole window; `h-full` pins
      the column so the list scrolls inside it and the action bar stays visible. --%>
      <div class="relative flex h-full flex-col overflow-hidden">
        <%!-- The title bar's book name is decorative chrome (aria-hidden); this
        heading carries the name for assistive tech and document structure. --%>
        <h1 class="sr-only">{@book.name}</h1>

        <%!-- The expenses header's conflict signal: an ambient bell shown only once a
        sync surfaces a conflict, never as a per-row marker on the list below. Absent
        while the Book is quiet, so the header takes no space until it has something to
        say. The bell toggles the "Synced changes" popup, which is anchored to this
        `relative` header so it hangs beneath the bell. --%>
        <div :if={@conflict_count > 0} class="relative flex justify-end pt-2 pr-2">
          <Bond.conflict_bell
            id="conflict-bell"
            count={@conflict_count}
            phx-click="toggle_synced_changes"
          />
          <Bond.synced_changes_popup
            :if={@synced_changes_open}
            id="synced-changes-popup"
            field_conflicts={@conflict_summary.field_conflicts}
            edit_delete_conflicts={@conflict_summary.edit_delete_conflicts}
            on_open_conflict="open_conflict"
            on_restore="restore_expense"
            on_keep_deleted="keep_deleted"
            on_dismiss_all="dismiss_all"
          />
        </div>

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
                date_display={Formatting.format_date(expense.date)}
                description={expense.description}
                amount_display={Formatting.format_amount(expense.cost)}
                category={Map.get(@category_names, expense.category_id)}
                phx-click="edit_expense"
                phx-value-id={expense.id}
              />
            </Bond.list_view>
          </div>
        </div>

        <div class="flex items-center gap-2 p-4">
          <Bond.button variant={:outline} phx-click="open_categories">Categories</Bond.button>
          <Bond.button variant={:outline} phx-click="open_report">Report</Bond.button>
        </div>

        <Bond.side_panel
          :if={@editor}
          id="expense-editor"
          title={Editor.title(@editor)}
          on_close="close_editor"
        >
          <Editor.panel
            editor={@editor}
            editor_tab={@editor_tab}
            form={@form}
            categories={@categories}
            conflict_summary={@conflict_summary}
            time_zone={@time_zone}
          />
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

  def handle_event("open_report", _params, socket) do
    # The Report is another in-window secondary page (ADR 0017).
    socket
    |> push_navigate(to: ~p"/books/#{socket.assigns.book.id}/report")
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

    case Tracking.quick_add_expense(book.id, line,
           today: Formatting.today(socket.assigns.time_zone)
         ) do
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
    socket
    |> Editor.open_new()
    |> noreply()
  end

  def handle_event("edit_expense", %{"id" => expense_id}, socket) do
    open_editor(socket, expense_id, :details)
  end

  # A row in the "Synced changes" popup opens straight to that Expense's Conflicts tab, not
  # the Details form — the row exists because a conflict is waiting there.
  def handle_event("open_conflict", %{"id" => expense_id}, socket) do
    open_editor(socket, expense_id, :conflicts)
  end

  def handle_event("validate_expense", %{"expense" => expense_params}, socket) do
    socket
    |> Editor.validate(expense_params)
    |> noreply()
  end

  def handle_event("save_expense", %{"expense" => expense_params}, socket) do
    socket
    |> Editor.save(expense_params)
    |> refresh_expenses()
    |> noreply()
  end

  # The bell opens and closes the "Synced changes" popup; it is only rendered while a
  # conflict signal is showing, so a toggle can never strand it over an empty header.
  def handle_event("toggle_synced_changes", _params, socket) do
    socket
    |> assign(synced_changes_open: not socket.assigns.synced_changes_open)
    |> noreply()
  end

  # Dismiss all clears the whole signal at once: the context drops the in-memory
  # conflicts and broadcasts, so `assign_conflicts/2` closes the popup and hides the bell.
  def handle_event("dismiss_all", _params, socket) do
    Tracking.dismiss_conflicts(socket.assigns.book.id)

    socket
    |> assign_conflicts(socket.assigns.book.id)
    |> noreply()
  end

  # Restore revives a deleted Expense from the dropped edit and clears that decision. It
  # changes the document, so the expense list reloads alongside the conflict count; the last
  # decision resolving drops the count to zero, which closes the popup and hides the bell.
  def handle_event("restore_expense", %{"id" => expense_id}, socket) do
    book_id = socket.assigns.book.id

    case Tracking.restore_expense(book_id, expense_id) do
      {:ok, _expense} ->
        socket
        |> assign(expenses: load_expenses(book_id))
        |> assign_conflicts(book_id)
        |> noreply()

      # The decision went away between render and click (a concurrent resync already resolved
      # it); re-read to settle the signal rather than surface an error for a no-op.
      {:error, :not_found} ->
        socket
        |> assign_conflicts(book_id)
        |> noreply()

      # A real failure — the write did not land — so say so and leave the decision standing
      # for a retry rather than swallow it as if the restore had happened.
      {:error, _reason} ->
        socket
        |> put_flash(:error, "Could not restore the expense.")
        |> assign_conflicts(book_id)
        |> noreply()
    end
  end

  # Keep deleted acknowledges the delete and drops just that decision. Nothing is revived and
  # the document is untouched, so only the conflict count re-reads — shrinking the badge, or
  # closing the popup when it was the last decision.
  def handle_event("keep_deleted", %{"id" => expense_id}, socket) do
    Tracking.keep_deleted(socket.assigns.book.id, expense_id)

    socket
    |> assign_conflicts(socket.assigns.book.id)
    |> noreply()
  end

  # Switch between the editor's Details and Conflicts tabs. An unknown value falls back to
  # Details, and the render only shows the Conflicts tab while a conflict is unresolved, so
  # a stale `:conflicts` selection resolves to the form once the conflict clears.
  def handle_event("select_editor_tab", %{"tab" => "conflicts"}, socket) do
    socket
    |> assign(editor_tab: :conflicts)
    |> noreply()
  end

  def handle_event("select_editor_tab", _params, socket) do
    socket
    |> assign(editor_tab: :details)
    |> noreply()
  end

  def handle_event(
        "make_conflict_value",
        %{"expense-id" => expense_id, "field" => field, "index" => index},
        socket
      ) do
    socket
    |> Editor.make_conflict_value(find_expense(socket, expense_id), expense_id, field, index)
    |> resync_after_conflict_action()
    |> noreply()
  end

  def handle_event("dismiss_conflict", %{"expense-id" => expense_id, "field" => field}, socket) do
    socket
    |> Editor.dismiss_conflict(expense_id, field)
    |> resync_after_conflict_action()
    |> noreply()
  end

  def handle_event("close_editor", _params, socket) do
    socket
    |> assign(editor: nil, confirm_delete: nil)
    |> noreply()
  end

  def handle_event("request_delete", _params, socket) do
    case socket.assigns.editor do
      %Editor{mode: :edit, expense: expense} ->
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

  defp failed(socket, message) do
    socket
    |> put_flash(:error, message)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    case Tracking.get_book(id) do
      %Tracking.Book{} = book ->
        # `page_title` drives the HTML title bar and document `<title>`, but the native
        # window's title does not follow it — push the new name to the shell too.
        DesktopShell.set_book_title(book)

        socket
        |> assign(book: book, expenses: load_expenses(id))
        |> assign_conflicts(id)
        |> put_title(book.name)
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
    |> Editor.reset_selected_category_if_gone()
    |> noreply()
  end

  # A change elsewhere may have deleted the expense currently open in the editor;
  # drop the stale editor rather than let a Save/Delete act on a phantom.
  defp close_editor_if_gone(socket) do
    case socket.assigns.editor do
      %Editor{mode: :edit, expense: %Expense{id: id}} ->
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

  # The badge count is every surfaced conflict — scalar and edit-vs-delete alike — since
  # each is one item needing attention; the full summary feeds the popup. A zero count
  # hides the bell, so a dismiss (or any drop to zero) also closes the popup rather than
  # strand it over an empty header.
  defp assign_conflicts(socket, id) do
    summary = load_conflict_summary(id)
    count = length(summary.field_conflicts) + length(summary.edit_delete_conflicts)

    socket
    |> assign(conflict_summary: summary, conflict_count: count)
    |> then(fn socket ->
      if count == 0, do: assign(socket, synced_changes_open: false), else: socket
    end)
  end

  defp load_conflict_summary(id) do
    case Tracking.conflict_summary(id) do
      {:error, :not_open} -> %{field_conflicts: [], edit_delete_conflicts: []}
      summary -> summary
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

  defp find_expense(socket, expense_id) do
    Enum.find(socket.assigns.expenses, &(&1.id == expense_id))
  end

  # Opens the editor for an existing expense on the requested tab. A row in the expenses list
  # asks for Details; a "Synced changes" popup row asks for Conflicts. Either way the popup
  # closes as the panel slides in. A vanished row (edited or deleted elsewhere) resyncs rather
  # than opening a stale editor.
  defp open_editor(socket, expense_id, requested_tab) do
    case find_expense(socket, expense_id) do
      %Expense{} = expense ->
        socket
        |> Editor.open_edit(expense, requested_tab)
        |> noreply()

      nil ->
        socket
        |> assign(expenses: load_expenses(socket.assigns.book.id), synced_changes_open: false)
        |> noreply()
    end
  end

  # The Book-view half of a conflict action: the `Editor` write and this refresh are the two
  # halves of one handler. Reloads the list and conflict summary the write changed, retires
  # the editor if its expense vanished, and settles the tab against the refreshed summary.
  defp resync_after_conflict_action(socket) do
    book_id = socket.assigns.book.id

    socket
    |> assign(expenses: load_expenses(book_id))
    |> assign_conflicts(book_id)
    |> close_editor_if_gone()
    |> Editor.settle_tab()
  end

  defp refresh_expenses(socket) do
    assign(socket, expenses: load_expenses(socket.assigns.book.id))
  end

  @doc """
  Reloads the category picker cache and the list's `%{id => name}` badge map together.

  The shared refresh behind the editor's deleted-category Save backstop, so
  `LocalCentsWeb.BookLive.Editor` drops a category from the picker and the list badges at
  once when a Save meets a category that was deleted out from under it (see ADR 0018).
  """
  @spec refresh_categories(Socket.t()) :: Socket.t()
  def refresh_categories(socket) do
    assign_categories(socket, load_categories(socket.assigns.book.id))
  end

  # The IANA time zone the browser reported on connect (e.g. "America/New_York"),
  # falling back to UTC on the static first render (no connect params yet).
  defp connected_time_zone(socket) do
    case get_connect_params(socket) do
      %{"time_zone" => time_zone} when is_binary(time_zone) -> time_zone
      _ -> "Etc/UTC"
    end
  end

  defp redirect_missing(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/library")
  end
end
