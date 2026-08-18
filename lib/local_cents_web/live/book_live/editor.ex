defmodule LocalCentsWeb.BookLive.Editor do
  @moduledoc """
  Provides functions for the `LocalCentsWeb.BookLive` slide-in editor.

  Its functions transform `BookLive`'s socket — they build the editor assigns (`editor`,
  `form`, `editor_tab`) and write through `LocalCents.Tracking` — and leave the Book-view
  refresh (reloading the expense list and the conflict summary) to the caller. The one
  exception is the deleted-category save backstop, which calls back to
  `BookLive.refresh_categories/1` so the picker cache and the list's badge map refresh
  together (see [ADR 0018](0018-category-assignment-through-the-editor.html)).
  """
  use LocalCentsWeb, :html

  import Phoenix.LiveView, only: [put_flash: 3]

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Expense
  alias LocalCentsWeb.BookLive
  alias LocalCentsWeb.BookLive.Formatting
  alias LocalCentsWeb.ConflictPresenter
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @typedoc """
  An open editing session: `:new` seeds a blank `Expense`, `:edit` carries the existing one.
  Replaces the untyped `{:new | :edit, Expense}` tuple that `BookLive` once threaded through
  its assigns. A view affordance, not a domain concept, so it lives in the web layer.
  """
  @type t() :: %__MODULE__{mode: :new | :edit, expense: Expense.t()}

  defstruct [:mode, :expense]

  @doc "The side-panel heading for the open editing session."
  @spec title(t()) :: String.t()
  def title(%__MODULE__{mode: :new}), do: "New Expense"
  def title(%__MODULE__{mode: :edit}), do: "Edit Expense"

  @doc """
  Opens a blank editor dated the user's local today, so the date field opens pre-filled. The
  seeded date only fills the empty field; a save re-reads the field, so it never persists on
  its own.
  """
  @spec open_new(Socket.t()) :: Socket.t()
  def open_new(socket) do
    today = today(socket)
    base = %Expense{date: today}

    assign(socket,
      editor: %__MODULE__{mode: :new, expense: base},
      editor_tab: :details,
      form: build_form(base, today)
    )
  end

  @doc """
  Opens the editor for an existing `Expense` on the requested tab. A row in the expenses
  list asks for `:details`; a "Synced changes" popup row asks for `:conflicts`. Either way
  the popup closes as the panel slides in.
  """
  @spec open_edit(Socket.t(), Expense.t(), requested_tab :: atom()) :: Socket.t()
  def open_edit(socket, %Expense{} = expense, requested_tab) do
    editor = %__MODULE__{mode: :edit, expense: expense}

    assign(socket,
      editor: editor,
      editor_tab: resolved_tab(requested_tab, editor, socket.assigns.conflict_summary),
      form: build_form(expense, today(socket)),
      synced_changes_open: false
    )
  end

  @doc """
  Rebuilds the form from what the user typed so validation errors surface as they edit.

  A concurrent `:book_updated` resync can close the editor before an in-flight
  `phx-change` arrives, so a nil editor is tolerated rather than a crash.
  """
  @spec validate(Socket.t(), expense_params :: map()) :: Socket.t()
  def validate(socket, expense_params) do
    case socket.assigns.editor do
      nil ->
        socket

      %__MODULE__{expense: base} ->
        assign(socket, form: build_form(base, today(socket), expense_params, :validate))
    end
  end

  @doc """
  Commits the form: adds a new `Expense` or fully replaces an edited one's editable fields.

  On success the editor closes; on a validation failure the form rebuilds so the user's
  input and the changeset errors survive; on the deleted-category backstop (ADR 0018) the
  selection clears and the picker cache refreshes. The caller reloads the expense list. A
  nil editor (a concurrent resync closed it) is a no-op.
  """
  @spec save(Socket.t(), expense_params :: map()) :: Socket.t()
  def save(socket, expense_params) do
    today = today(socket)

    case socket.assigns.editor do
      %__MODULE__{mode: :new, expense: base} ->
        save_new(socket, base, expense_params, today)

      %__MODULE__{mode: :edit, expense: expense} ->
        save_edit(socket, expense, expense_params, today)

      nil ->
        socket
    end
  end

  defp save_new(socket, base, expense_params, today) do
    case Tracking.add_expense(socket.assigns.book.id, expense_params, today: today) do
      {:ok, _expense} -> saved(socket)
      {:error, %Ecto.Changeset{}} -> invalid(socket, base, expense_params, today)
      {:error, :category_not_found} -> category_gone(socket, base, expense_params, today)
      {:error, _reason} -> failed(socket, "Could not save the expense.")
    end
  end

  defp save_edit(socket, expense, expense_params, today) do
    case Tracking.edit_expense(socket.assigns.book.id, expense.id, expense_params, today: today) do
      {:ok, _expense} -> saved(socket)
      {:error, %Ecto.Changeset{}} -> invalid(socket, expense, expense_params, today)
      {:error, :not_found} -> saved(socket, "That expense no longer exists.")
      {:error, :category_not_found} -> category_gone(socket, expense, expense_params, today)
      {:error, _reason} -> failed(socket, "Could not save the expense.")
    end
  end

  # Clear `confirm_delete` alongside the editor: if the delete-confirm modal were open (via
  # a race) when a save succeeds, leaving it set would strand the modal after the editor closed.
  defp saved(socket, flash \\ nil) do
    socket
    |> maybe_flash(flash)
    |> assign(editor: nil, confirm_delete: nil)
  end

  defp maybe_flash(socket, nil), do: socket
  defp maybe_flash(socket, message), do: put_flash(socket, :info, message)

  # A submit that failed validation: rebuild the form from what the user typed so their
  # input survives and the changeset's errors surface (every field counts as used on a
  # submit, so `used_input?/1` lets them all show).
  defp invalid(socket, base, expense_params, today) do
    assign(socket, form: build_form(base, today, expense_params, :validate))
  end

  defp failed(socket, message) do
    put_flash(socket, :error, message)
  end

  # The picked category was deleted between opening the editor and saving (the
  # `:category_not_found` backstop from ADR 0018). Refresh the cache, clear the now
  # dangling selection, and keep the user's other input so they can re-file and retry
  # rather than lose the edit.
  defp category_gone(socket, base, expense_params, today) do
    socket
    |> put_flash(:error, "That category no longer exists — it was cleared.")
    |> BookLive.refresh_categories()
    |> assign(form: blank_category_form(base, expense_params, today))
  end

  @doc """
  Makes the chosen alternative the value: override to it through the same `edit_expense`
  Save uses, then drop the settled conflict. A vanished expense, index, or register falls
  back to dismissing the stale conflict; the caller then reloads and retires a gone editor.
  """
  @spec make_conflict_value(
          Socket.t(),
          expense :: Expense.t() | nil,
          expense_id :: String.t(),
          field :: String.t(),
          index :: String.t()
        ) :: Socket.t()
  def make_conflict_value(socket, expense, expense_id, field, index) do
    conflicts = socket.assigns.conflict_summary.field_conflicts

    with %Expense{} = expense <- expense,
         {:ok, value} <- ConflictPresenter.alternative_value(conflicts, expense_id, field, index) do
      override(socket, expense, field, value)
    else
      _ -> dismiss(socket, expense_id, field)
    end
  end

  @doc """
  Dismisses one conflict: accept what LocalCents kept and clear just this one, leaving the
  others. Drops only the in-memory summary entry; the caller reloads and settles the tab.
  """
  @spec dismiss_conflict(Socket.t(), expense_id :: String.t(), field :: String.t()) :: Socket.t()
  def dismiss_conflict(socket, expense_id, field) do
    dismiss(socket, expense_id, field)
  end

  # Override to a chosen alternative through the same `edit_expense` Save uses, writing just
  # the conflicted field (the changeset casts it onto the existing expense, so the rest is
  # kept). The write collapses the conflicting register — it "wins going forward" — and the
  # caller's conflict reload updates the badge and removes the tab.
  defp override(socket, %Expense{} = expense, field, value) do
    book_id = socket.assigns.book.id
    today = today(socket)

    case Tracking.edit_expense(book_id, expense.id, %{field => value}, today: today) do
      {:ok, updated} ->
        _ = Tracking.dismiss_field_conflict(book_id, expense.id, field)

        assign(socket,
          editor: %__MODULE__{mode: :edit, expense: updated},
          form: build_form(updated, today)
        )

      # The expense went away between render and click (a concurrent resync); drop the stale
      # summary entry and let the caller's `close_editor_if_gone/1` retire the panel.
      {:error, :not_found} ->
        dismiss(socket, expense.id, field)

      {:error, _reason} ->
        failed(socket, "Could not update the expense.")
    end
  end

  defp dismiss(socket, expense_id, field) do
    _ = Tracking.dismiss_field_conflict(socket.assigns.book.id, expense_id, field)
    socket
  end

  @doc """
  Falls back to the Details tab once the open expense has no conflict left, so a resolved
  conflict never strands the editor on a Conflicts tab that is no longer rendered. Called
  after a conflict reload, when the refreshed summary decides the tab set.
  """
  @spec settle_tab(Socket.t()) :: Socket.t()
  def settle_tab(socket) do
    if editor_conflicts(socket.assigns.editor, socket.assigns.conflict_summary) == [] do
      assign(socket, editor_tab: :details)
    else
      socket
    end
  end

  @doc """
  Clears the open editor's category selection when the picked category was just deleted
  (via a `:categories_updated` broadcast), so the picker and a later Save agree. Rebuilds
  from the form's current params so the user's unsaved date/description/cost survives; only
  the category resets.
  """
  @spec reset_selected_category_if_gone(Socket.t()) :: Socket.t()
  def reset_selected_category_if_gone(%{assigns: %{editor: nil}} = socket), do: socket

  def reset_selected_category_if_gone(socket) do
    selected = socket.assigns.form[:category_id].value

    cond do
      not present?(selected) -> socket
      category_exists?(socket.assigns.categories, selected) -> socket
      true -> clear_selected_category(socket)
    end
  end

  defp clear_selected_category(socket) do
    base = socket.assigns.editor.expense
    form = blank_category_form(base, socket.assigns.form.params, today(socket))
    assign(socket, form: form)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp category_exists?(categories, id), do: Enum.any?(categories, &(&1.id == id))

  defp today(socket), do: Formatting.today(socket.assigns.time_zone)

  # Only land on the Conflicts tab when the expense actually has a conflict to show; otherwise
  # (or when Details was asked for) open the form, so a Conflicts request can never open an
  # empty panel.
  defp resolved_tab(:conflicts, editor, summary) do
    if editor_conflicts(editor, summary) == [], do: :details, else: :conflicts
  end

  defp resolved_tab(_requested, _editor, _summary), do: :details

  # The scalar conflicts on the open expense (empty for a new or unconflicted one), the set
  # that decides whether the editor shows tabs at all.
  defp editor_conflicts(%__MODULE__{mode: :edit, expense: %Expense{id: id}}, summary) do
    Enum.filter(summary.field_conflicts, &(&1.expense_id == id))
  end

  defp editor_conflicts(_editor, _summary), do: []

  # Builds the editor form from the Expense changeset (see ADR 0016 — Ecto for validation,
  # with `phoenix_ecto` supplying the form binding). The form action is a UI concern, so it
  # lives here at the call site rather than in the domain changeset: a nil action (on open)
  # hides errors, `:validate` surfaces them on change and on a failed submit.
  defp build_form(expense, today, params \\ %{}, action \\ nil) do
    expense
    |> Expense.changeset(params, today)
    |> to_form(action: action)
  end

  # Rebuild the editor form with the category selection cleared (Uncategorized) while keeping
  # the user's other input — the shared shape behind both the Save-time backstop and the live
  # vanished-selection reset (see ADR 0018).
  defp blank_category_form(base, params, today) do
    build_form(base, today, Map.put(params, "category_id", ""), :validate)
  end

  # The editor body: the Details form, plus a Conflicts tab that appears only while the open
  # Expense carries an unresolved scalar conflict and vanishes the moment it resolves. A new
  # (unsaved) Expense never conflicts, so it never shows tabs. Both `@editor` and
  # `@conflict_summary` are already in the socket, so the tab set is derived here rather than
  # tracked as its own assign.
  attr :editor, __MODULE__, required: true
  attr :editor_tab, :atom, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true
  attr :conflict_summary, :map, required: true
  attr :time_zone, :string, required: true

  @spec panel(Socket.assigns()) :: Rendered.t()
  def panel(assigns) do
    conflicts = editor_conflicts(assigns.editor, assigns.conflict_summary)

    assigns =
      assign(assigns,
        has_conflicts: conflicts != [],
        conflict_views: ConflictPresenter.views(conflicts, assigns.time_zone)
      )

    ~H"""
    <%!-- Two plain labeled buttons that swap the panel below, not a full ARIA tab widget
    (no `role="tablist"`): that pattern promises arrow-key navigation this does not implement,
    and a half-built one reads worse to a screen reader than clear buttons. --%>
    <div :if={@has_conflicts} class="mb-4 flex gap-5 border-b border-white/10">
      <button
        type="button"
        phx-click="select_editor_tab"
        phx-value-tab="details"
        class={tab_class(@editor_tab == :details)}
      >
        Details
      </button>
      <button
        type="button"
        phx-click="select_editor_tab"
        phx-value-tab="conflicts"
        class={tab_class(@editor_tab == :conflicts)}
      >
        Conflicts
      </button>
    </div>

    <.form
      :if={not @has_conflicts or @editor_tab == :details}
      for={@form}
      id="expense-form"
      phx-submit="save_expense"
      phx-change="validate_expense"
      class="space-y-3"
    >
      <Bond.input field={@form[:date]} type="date" label="Date" variant="frosted" class="w-full" />
      <Bond.input field={@form[:description]} label="Description" variant="frosted" class="w-full" />
      <Bond.input
        field={@form[:cost]}
        label="Cost"
        variant="frosted"
        class="w-full"
        placeholder="0.00"
      />
      <%!-- Filing is a plain form field (ADR 0018): a blank selection is Uncategorized.
      With no categories yet, the editor can't create one (that is the Categories view's
      job), so show a hint instead of a dead select. --%>
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
        <%!-- Delete only exists for a saved expense; a spacer keeps Save pinned right when
        adding, since the row is justify-between. --%>
        <Bond.button
          :if={@editor.mode == :edit}
          type="button"
          variant={:destructive}
          phx-click="request_delete"
        >
          Delete
        </Bond.button>
        <span :if={@editor.mode == :new}></span>
        <Bond.button type="submit">{submit_label(@editor)}</Bond.button>
      </div>
    </.form>

    <Bond.expense_conflicts
      :if={@has_conflicts and @editor_tab == :conflicts}
      id="expense-conflicts"
      conflicts={@conflict_views}
      on_make_value="make_conflict_value"
      on_dismiss="dismiss_conflict"
    />
    """
  end

  # Highlights the active tab against the dark editor panel; both share the same padding so
  # switching never shifts the row.
  defp tab_class(active?) do
    base = "px-1 pb-2 text-sm font-semibold -mb-px border-b-2 transition-colors"

    if active? do
      base <> " border-primary-400 text-white"
    else
      base <> " border-transparent text-surface-400 hover:text-white"
    end
  end

  # The `<select>` options as `{name, id}` pairs; a blank option (Uncategorized) is supplied
  # by `Bond.select` itself.
  defp category_options(categories), do: Enum.map(categories, &{&1.name, &1.id})

  # "Create" for the new-expense form submit, "Save" for edits — the house UI vocabulary
  # (see docs/ui-language.md: "New" to initiate, "Create" to submit).
  defp submit_label(%__MODULE__{mode: :new}), do: "Create"
  defp submit_label(%__MODULE__{mode: :edit}), do: "Save"
end
