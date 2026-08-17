defmodule LocalCentsWeb.Bond.Composites.ExpenseConflicts do
  @moduledoc """
  The editor's **Conflicts tab** — the scalar detail behind an auto-resolved conflict.

  A sync can fold two devices' concurrent edits to the same Expense field into one kept
  value, keeping the others as alternatives (surfaced first through the bell and the
  "Synced changes" popup — see `LocalCentsWeb.Bond.Composites.SyncedChangesPopup`). This
  panel is where a user judges that choice: for each conflicted field it shows the value
  LocalCents kept, then every other edit, each with provenance — which device made it and
  when.

  Two actions per conflict. **Make this the value** pushes `on_make_value` for a chosen
  alternative (tagged with the Expense id, the `field`, and the alternative's `index`), a
  normal edit that wins going forward. **Dismiss conflict** pushes `on_dismiss` (tagged
  with the Expense id and `field`), accepting the kept value and clearing just this one.

  The caller renders this only while the open Expense has an unresolved conflict and drops it
  the moment the conflict resolves, so the panel never shows a settled conflict. Each
  `conflict` arrives display-ready, its values and provenance formatted by the caller. No copy
  here names Automerge or CRDTs, and none assumes exactly two edits — the register can hold
  more than two, so a conflict lists one kept value and N others.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, required: true, doc: "DOM id for the panel wrapper"

  attr :conflicts, :list,
    required: true,
    doc:
      "Display-ready conflicts for the open Expense, each `%{expense_id, field, field_label, kept: %{value, provenance}, alternatives: [%{index, value, provenance}]}`"

  attr :on_make_value, :string,
    required: true,
    doc:
      "Event pushed with `phx-value-expense-id`, `phx-value-field`, and `phx-value-index` when an alternative's Make this the value is clicked"

  attr :on_dismiss, :string,
    required: true,
    doc:
      "Event pushed with `phx-value-expense-id` and `phx-value-field` when Dismiss conflict is clicked"

  @spec expense_conflicts(Socket.assigns()) :: Rendered.t()
  def expense_conflicts(assigns) do
    ~H"""
    <div id={@id} class="space-y-6">
      <section :for={conflict <- @conflicts} class="space-y-3">
        <div>
          <h3 class="text-sm font-semibold text-surface-800">{conflict.field_label}</h3>
          <%!-- "Different devices" and "one" keep the copy right whether two or more edits
          collided — the register can hold more than two. --%>
          <p class="mt-0.5 text-xs text-surface-500">
            Different devices edited this {conflict.field_label} while apart. LocalCents kept one
            value — make another the value, or dismiss to accept the kept one.
          </p>
        </div>

        <div class="rounded-lg border border-primary-300 bg-primary-50/60 px-3 py-2">
          <p class="text-[0.625rem] font-bold uppercase tracking-wide text-primary-700">
            Kept by LocalCents
          </p>
          <p class="mt-0.5 text-sm font-medium text-surface-800">{conflict.kept.value}</p>
          <p class="text-[11px] text-surface-500">{conflict.kept.provenance}</p>
        </div>

        <div class="space-y-2">
          <p class="text-[0.625rem] font-bold uppercase tracking-wide text-surface-400">
            Other edits
          </p>
          <div
            :for={alternative <- conflict.alternatives}
            id={"#{@id}-#{conflict.field}-#{alternative.index}"}
            class="flex items-center gap-3 rounded-lg border border-surface-200 px-3 py-2"
          >
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-surface-800">
                {alternative.value}
              </span>
              <span class="block text-[11px] text-surface-500">{alternative.provenance}</span>
            </span>
            <button
              type="button"
              phx-click={@on_make_value}
              phx-value-expense-id={conflict.expense_id}
              phx-value-field={conflict.field}
              phx-value-index={alternative.index}
              class="shrink-0 rounded border border-primary-700 px-2 py-1 text-[11px] font-medium text-primary-700 hover:bg-primary-100"
            >
              Make this the value
            </button>
          </div>
        </div>

        <button
          type="button"
          phx-click={@on_dismiss}
          phx-value-expense-id={conflict.expense_id}
          phx-value-field={conflict.field}
          class="text-[11px] font-medium text-surface-500 hover:text-primary-800 hover:underline"
        >
          Dismiss conflict
        </button>
      </section>
    </div>
    """
  end
end
