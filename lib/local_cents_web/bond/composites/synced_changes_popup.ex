defmodule LocalCentsWeb.Bond.Composites.SyncedChangesPopup do
  @moduledoc """
  The "Synced changes" popup — the triage surface that opens from the conflict bell.

  A sync can fold in edits that need the user's eye, and the bell only says *how many*
  (see `LocalCentsWeb.Bond.Elements.ConflictBell`). This popup is where they are read:
  changes grouped by the action each needs, so the user can tell at a glance which are
  informational and which want a decision (the grouped treatment settled by the
  [#220 conflict UX](https://github.com/zorn/local_cents/issues/220), over an activity
  feed or a flat list).

  Changes group by the action each needs. The **Auto-resolved** group carries the scalar
  conflicts LocalCents merged on its own, one row each: a row names the value LocalCents
  kept and, clicked, opens that Expense's editor (`on_open_conflict`, pushed with the
  Expense's id in `phx-value-id`). The **Needs your decision** group carries the dropped
  edits — an Expense edited here that the other peer deleted: each row names the dropped
  edit and offers **Restore** (revive the Expense — `on_restore`) or **Keep deleted** (accept
  the delete — `on_keep_deleted`), both pushed with the Expense's id. **Dismiss all** clears
  the whole signal at once (`on_dismiss_all`). Each group's label is hidden when it has no
  rows, so a summary that holds only one kind never heads an empty section.

  No copy names Automerge or CRDTs, and none assumes exactly two conflicting edits: the
  register can hold more than two, so a scalar row says only that LocalCents kept one.

  The caller renders this while it should be shown (typically an `@…_open` assign toggled
  by the bell) and removes it to dismiss, the same open/closed-by-the-caller contract as
  `LocalCentsWeb.Bond.Layouts.Modal`.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias LocalCentsWeb.ConflictPresenter
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, required: true, doc: "DOM id for the popup wrapper"

  attr :field_conflicts, :list,
    required: true,
    doc:
      "The auto-resolved scalar conflicts, each a `t:LocalCents.Tracking.BookDocument.conflict_summary/0` `field_conflict` (`expense_id`, `field`, `kept`, `alternatives`)"

  attr :edit_delete_conflicts, :list,
    required: true,
    doc:
      "The edit-vs-delete conflicts, each a `t:LocalCents.Tracking.BookDocument.conflict_summary/0` `edit_delete_conflict` (`expense_id`, `expense`, `device`, `time`)"

  attr :on_open_conflict, :string,
    required: true,
    doc: "LiveView event pushed with the Expense's id in `phx-value-id` when a row is clicked"

  attr :on_restore, :string,
    required: true,
    doc: "LiveView event pushed with the Expense's id in `phx-value-id` when Restore is clicked"

  attr :on_keep_deleted, :string,
    required: true,
    doc:
      "LiveView event pushed with the Expense's id in `phx-value-id` when Keep deleted is clicked"

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
              Synced edits to {ConflictPresenter.field_label(conflict.field)} — LocalCents kept one.
            </span>
          </span>
          <.icon name="hero-chevron-right" class="size-4 text-surface-300" />
        </button>

        <div :if={@edit_delete_conflicts != []} class="px-3 pt-2.5 pb-1">
          <p class="text-[0.625rem] font-bold uppercase tracking-wide text-surface-400">
            Needs your decision
          </p>
        </div>
        <%!-- A deleted Expense has no row in the list to mark, so its dropped edit is handled
        here: the row names the edit LocalCents held on to and offers to revive it or accept
        the delete. Restore is the emphasized recovery action; Keep deleted is the quieter
        accept. --%>
        <div
          :for={conflict <- @edit_delete_conflicts}
          id={"needs-decision-#{conflict.expense_id}"}
          class="flex items-start gap-2.5 px-3 py-2.5"
        >
          <.icon name="hero-trash" class="mt-0.5 size-4 shrink-0 text-error-600" />
          <div class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-surface-800">
              {conflict.expense.description}
            </span>
            <span class="block text-[11px] text-surface-500">
              Deleted on another device — your edit is still here.
            </span>
            <div class="mt-1.5 flex gap-3">
              <button
                type="button"
                phx-click={@on_restore}
                phx-value-id={conflict.expense_id}
                class="text-[11px] font-semibold text-primary-700 hover:underline"
              >
                Restore
              </button>
              <button
                type="button"
                phx-click={@on_keep_deleted}
                phx-value-id={conflict.expense_id}
                class="text-[11px] font-medium text-surface-500 hover:underline"
              >
                Keep deleted
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
