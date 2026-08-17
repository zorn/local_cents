defmodule LocalCentsWeb.Bond.Composites.SyncedChangesPopup do
  @moduledoc """
  The "Synced changes" popup — the triage surface that opens from the conflict bell.

  A sync can fold in edits that need the user's eye, and the bell only says *how many*
  (see `LocalCentsWeb.Bond.Elements.ConflictBell`). This popup is where they are read:
  changes grouped by the action each needs, so the user can tell at a glance which are
  informational and which want a decision (the grouped treatment settled by the
  [#220 conflict UX](https://github.com/zorn/local_cents/issues/220), over an activity
  feed or a flat list).

  This slice carries the **Auto-resolved** group only: the scalar conflicts LocalCents
  merged on its own, one row each. A row names the value LocalCents kept and, clicked,
  opens that Expense's editor (`on_open_conflict`, pushed with the Expense's id in
  `phx-value-id`). **Dismiss all** clears the whole signal at once (`on_dismiss_all`).
  The second group — deletes that need a Restore / Keep-deleted decision — lands in a
  later slice, so `edit_delete_conflicts` are not rendered here yet.

  No copy names Automerge or CRDTs, and none assumes exactly two conflicting edits: the
  register can hold more than two, so a row says only that LocalCents kept one.

  The caller renders this while it should be shown (typically an `@…_open` assign toggled
  by the bell) and removes it to dismiss, the same open/closed-by-the-caller contract as
  `LocalCentsWeb.Bond.Layouts.Modal`.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, required: true, doc: "DOM id for the popup wrapper"

  attr :field_conflicts, :list,
    required: true,
    doc:
      "The auto-resolved scalar conflicts, each a `t:LocalCents.Tracking.BookDocument.conflict_summary/0` `field_conflict` (`expense_id`, `field`, `kept`, `alternatives`)"

  attr :on_open_conflict, :string,
    required: true,
    doc: "LiveView event pushed with the Expense's id in `phx-value-id` when a row is clicked"

  attr :on_dismiss_all, :string,
    required: true,
    doc: "LiveView event pushed when Dismiss all is clicked"

  @spec synced_changes_popup(Socket.assigns()) :: Rendered.t()
  def synced_changes_popup(assigns) do
    ~H"""
    <div
      id={@id}
      class="absolute right-2 top-12 z-40 w-80 overflow-hidden rounded-lg border border-surface-200 bg-surface-50 shadow-xl"
    >
      <div class="flex items-center justify-between border-b border-surface-100 px-3 py-2">
        <span class="text-xs font-semibold tracking-wide text-surface-700">Synced changes</span>
        <button
          type="button"
          phx-click={@on_dismiss_all}
          class="text-[11px] font-medium text-primary-700 hover:underline"
        >
          Dismiss all
        </button>
      </div>

      <div class="max-h-[60vh] divide-y divide-surface-100 overflow-y-auto">
        <%!-- The badge counts every surfaced conflict, but this slice renders only the
        auto-resolved ones — so hide the group label when it would head an empty list
        (e.g. a summary holding only the deletes the next slice will show). --%>
        <div :if={@field_conflicts != []} class="px-3 pt-2.5 pb-1">
          <p class="text-[0.625rem] font-bold uppercase tracking-wide text-surface-400">
            Auto-resolved
          </p>
        </div>
        <%!-- A scalar conflict's kept value is the winning field value itself, so the row
        names it directly; clicking opens that Expense's editor. --%>
        <button
          :for={conflict <- @field_conflicts}
          type="button"
          phx-click={@on_open_conflict}
          phx-value-id={conflict.expense_id}
          class="flex w-full items-center gap-2.5 px-3 py-2.5 text-left hover:bg-surface-100"
        >
          <.icon name="hero-arrows-pointing-in" class="size-4 shrink-0 text-warning-600" />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-surface-800">
              {conflict.kept.value}
            </span>
            <span class="block text-[11px] text-surface-500">
              Synced edits to {field_label(conflict.field)} — LocalCents kept one.
            </span>
          </span>
          <.icon name="hero-chevron-right" class="size-4 text-surface-300" />
        </button>
      </div>
    </div>
    """
  end

  # A stored field name ("description") to its display label ("Description"). Only
  # `description` is a scalar today; capitalizing keeps the copy right as more fields
  # gain conflict handling.
  defp field_label(field), do: String.capitalize(field)
end
