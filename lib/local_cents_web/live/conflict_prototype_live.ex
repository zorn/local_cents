defmodule LocalCentsWeb.ConflictPrototypeLive do
  @moduledoc """
  THROWAWAY UI PROTOTYPE — issue #220 (wayfinder map #210).

  Answers "what should the Automerge conflict experience look and feel like?"

  The frame is settled: an ambient **notification bell + numbered badge** is the only
  signal (no per-row markers), the popup carries a **Dismiss all**, and per-entity
  conflict detail lives inside the expense editor under a **Conflicts** tab that is
  present only while an unresolved conflict exists. The three variants now vary just
  the **popup menu** — its layout and its copy — switchable via `?variant=a|b|c`:

    - a — Grouped by action (auto-resolved vs needs-decision), title "Synced changes"
    - b — Activity feed (one-sentence rows), title "Sync activity"
    - c — Compact (name + plain-English line), title "Conflicts"

  Not production code. No tests, no real mutations — override/restore/dismiss only
  mutate local assigns. Dev-only route: `/dev/conflict-prototype`. Delete once the
  direction is settled; the winner gets rebuilt against real conflict metadata
  bubbled up from `ExAutomerge`.
  """
  use LocalCentsWeb, :live_view

  @variants ~w(a b c)

  @mac "Mike's MacBook"
  @web "Safari (browser)"

  defp seed_expenses do
    [
      %{
        id: "e1",
        date_display: "08/09/2026",
        description: "1% milk",
        amount_display: "$4.29",
        category: "Groceries",
        conflict: %{
          field: :description,
          winner: %{value: "1% milk", device: @mac, at: "today 2:14 PM"},
          loser: %{value: "Chocolate milk", device: @web, at: "today 2:09 PM"}
        }
      },
      %{
        id: "e2",
        date_display: "08/09/2026",
        description: "Morning coffee",
        amount_display: "$5.75",
        category: "Dining",
        conflict: nil
      },
      %{
        id: "e3",
        date_display: "08/08/2026",
        description: "Gas station",
        amount_display: "$52.10",
        category: "Auto",
        conflict: %{
          field: :cost,
          winner: %{value: "$52.10", device: @mac, at: "yesterday 6:02 PM"},
          loser: %{value: "$25.10", device: @web, at: "yesterday 5:58 PM"}
        }
      },
      %{
        id: "e4",
        date_display: "08/08/2026",
        description: "Pharmacy",
        amount_display: "$18.44",
        category: "Health",
        conflict: nil
      },
      %{
        id: "e5",
        date_display: "08/07/2026",
        description: "Electric bill",
        amount_display: "$96.20",
        category: "Utilities",
        conflict: nil
      },
      %{
        id: "e6",
        date_display: "08/07/2026",
        description: "Lunch — deli",
        amount_display: "$12.50",
        category: "Dining",
        conflict: nil
      }
    ]
  end

  # The delete case has no row to mark: edited on the Mac, deleted in the browser,
  # concurrently. The delete won; the edit vanished.
  defp seed_deletes do
    [
      %{
        id: "d1",
        date_display: "08/08/2026",
        description: "Costco run",
        amount_display: "$137.44",
        category: "Groceries",
        deleted: %{device: @web, at: "today 1:30 PM"},
        dropped_edit: %{
          field: :cost,
          value: "$137.44",
          was: "$127.44",
          device: @mac,
          at: "today 1:45 PM"
        }
      }
    ]
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     # :desktop so the layout omits the floating debug pill, which otherwise
     # overlaps the side-panel footer (prototype-only concern).
     |> assign(:client, :desktop)
     |> assign(:expenses, seed_expenses())
     |> assign(:deletes, seed_deletes())
     |> assign(:resolved, %{})
     |> assign(:delete_status, %{})
     |> assign(:inbox_open, false)
     # editor: nil | %{id: string, tab: :details | :conflicts}
     |> assign(:editor, nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    variant = if params["variant"] in @variants, do: params["variant"], else: "a"
    {:noreply, assign(socket, :variant, variant)}
  end

  # ── Switcher ─────────────────────────────────────────────────────────────────

  @impl Phoenix.LiveView
  def handle_event("cycle", %{"dir" => dir}, socket) do
    idx = Enum.find_index(@variants, &(&1 == socket.assigns.variant)) || 0
    delta = if dir == "prev", do: -1, else: 1
    next = Enum.at(@variants, Integer.mod(idx + delta, length(@variants)))

    {:noreply,
     socket
     |> assign(inbox_open: false, editor: nil)
     |> push_patch(to: ~p"/dev/conflict-prototype?variant=#{next}")}
  end

  # ── Inbox ────────────────────────────────────────────────────────────────────

  def handle_event("toggle_inbox", _params, socket) do
    {:noreply, assign(socket, :inbox_open, not socket.assigns.inbox_open)}
  end

  def handle_event("close_inbox", _params, socket) do
    {:noreply, assign(socket, :inbox_open, false)}
  end

  def handle_event("dismiss_all", _params, socket) do
    %{expenses: expenses, deletes: deletes, resolved: resolved, delete_status: status} =
      socket.assigns

    resolved =
      expenses
      |> Enum.filter(&conflicting?(&1, resolved))
      |> Enum.reduce(resolved, fn e, acc -> Map.put(acc, e.id, e.conflict.winner.value) end)

    status =
      deletes
      |> pending_deletes(status)
      |> Enum.reduce(status, fn d, acc -> Map.put(acc, d.id, :dismissed) end)

    {:noreply, assign(socket, resolved: resolved, delete_status: status, inbox_open: false)}
  end

  # ── Editor ───────────────────────────────────────────────────────────────────

  def handle_event("open_editor", %{"id" => id} = params, socket) do
    tab = if params["tab"] == "conflicts", do: :conflicts, else: :details
    {:noreply, assign(socket, editor: %{id: id, tab: tab}, inbox_open: false)}
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply, assign(socket, :editor, nil)}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab = if tab == "conflicts", do: :conflicts, else: :details
    {:noreply, assign(socket, :editor, Map.put(socket.assigns.editor, :tab, tab))}
  end

  # ── Resolution ───────────────────────────────────────────────────────────────

  def handle_event("choose", %{"id" => id, "value" => value}, socket) do
    {:noreply, assign(socket, :resolved, Map.put(socket.assigns.resolved, id, value))}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :delete_status, Map.put(socket.assigns.delete_status, id, :restored))}
  end

  def handle_event("dismiss_delete", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :delete_status, Map.put(socket.assigns.delete_status, id, :dismissed))}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      client={@client}
      window_title="Conflict Prototype"
      back_path={~p"/library"}
    >
      <.screen {assigns}>
        <.popup_grouped :if={@variant == "a"} {assigns} />
        <.popup_feed :if={@variant == "b"} {assigns} />
        <.popup_compact :if={@variant == "c"} {assigns} />
      </.screen>
      <.switcher variant={@variant} />
    </Layouts.app>
    """
  end

  # ── Shared screen shell (identical across variants; only the popup differs) ───

  attr :expenses, :list, required: true
  attr :resolved, :map, required: true
  attr :deletes, :list, required: true
  attr :delete_status, :map, required: true
  attr :inbox_open, :boolean, required: true
  attr :editor, :map, default: nil
  slot :inner_block, doc: "the variant's popup menu"

  defp screen(assigns) do
    ~H"""
    <div class="relative flex min-h-0 flex-1 flex-col overflow-hidden">
      <Bond.list_view fill>
        <:header>
          <div class="flex items-center justify-between px-4 py-2.5">
            <span class="text-xs font-semibold uppercase tracking-wide text-surface-500">Expenses</span>
            <.conflict_bell count={notif_count(assigns)} />
          </div>
        </:header>

        <.expense_rows expenses={@expenses} resolved={@resolved} />
      </Bond.list_view>

      <%!-- Popup rendered outside list_view so its overflow-hidden can't clip it --%>
      {render_slot(@inner_block)}

      <.expense_editor :if={@editor} editor={@editor} expenses={@expenses} resolved={@resolved} />
    </div>
    """
  end

  # ── Popup variant A — grouped by action needed ───────────────────────────────

  defp popup_grouped(assigns) do
    assigns = assign_conflict_lists(assigns)

    ~H"""
    <.popup_shell :if={@inbox_open} title="Synced changes" empty={@scalars == [] and @dels == []}>
      <div :if={@scalars != []} class="px-3 pt-2.5 pb-1">
        <p class="text-[10px] font-bold uppercase tracking-wide text-surface-400">Auto-resolved</p>
      </div>
      <button
        :for={e <- @scalars}
        phx-click="open_editor"
        phx-value-id={e.id}
        phx-value-tab="conflicts"
        class="flex w-full items-center gap-2.5 px-3 py-2.5 text-left hover:bg-surface-50"
      >
        <.icon name="hero-arrows-pointing-in" class="w-4 h-4 text-warning-600 shrink-0" />
        <span class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-surface-800 truncate">{resolved_value(
            e,
            @resolved
          )}</span>
          <span class="block text-[11px] text-surface-500">
            Conflicting {field_label(e.conflict.field)} — kept one of two edits
          </span>
        </span>
        <.icon name="hero-chevron-right" class="w-4 h-4 text-surface-300" />
      </button>

      <div :if={@dels != []} class="px-3 pt-2.5 pb-1 border-t border-surface-100">
        <p class="text-[10px] font-bold uppercase tracking-wide text-surface-400">
          Needs your decision
        </p>
      </div>
      <.delete_popup_row
        :for={d <- @dels}
        delete={d}
        subtitle="Deleted during sync — your edit was dropped"
      />
    </.popup_shell>
    """
  end

  # ── Popup variant B — activity feed of one-sentence rows ─────────────────────

  defp popup_feed(assigns) do
    assigns = assign_conflict_lists(assigns)

    ~H"""
    <.popup_shell :if={@inbox_open} title="Sync activity" empty={@scalars == [] and @dels == []}>
      <button
        :for={e <- @scalars}
        phx-click="open_editor"
        phx-value-id={e.id}
        phx-value-tab="conflicts"
        class="flex w-full items-start gap-2.5 px-3 py-2.5 text-left hover:bg-surface-50"
      >
        <.icon name="hero-arrows-pointing-in" class="w-4 h-4 text-warning-600 shrink-0 mt-0.5" />
        <span class="flex-1 min-w-0">
          <span class="block text-sm text-surface-800 leading-snug">
            Kept one of two edits to the {field_label(e.conflict.field)} of <span class="font-medium">“{resolved_value(e, @resolved)}”</span>.
          </span>
          <span class="block text-[11px] text-surface-400 mt-0.5">{e.conflict.winner.at}</span>
        </span>
      </button>

      <div :for={d <- @dels} class="flex items-start gap-2.5 px-3 py-2.5 border-t border-surface-100">
        <.icon name="hero-trash" class="w-4 h-4 text-warning-600 shrink-0 mt-0.5" />
        <div class="flex-1 min-w-0">
          <p class="text-sm text-surface-800 leading-snug">
            <span class="font-medium">“{d.description}”</span>
            was deleted during sync; your edit was dropped.
          </p>
          <p class="text-[11px] text-surface-400 mt-0.5">{d.deleted.at}</p>
          <.delete_actions delete={d} />
        </div>
      </div>
    </.popup_shell>
    """
  end

  # ── Popup variant C — compact name + plain-English line ──────────────────────

  defp popup_compact(assigns) do
    assigns = assign_conflict_lists(assigns)

    ~H"""
    <.popup_shell :if={@inbox_open} title="Conflicts" empty={@scalars == [] and @dels == []}>
      <button
        :for={e <- @scalars}
        phx-click="open_editor"
        phx-value-id={e.id}
        phx-value-tab="conflicts"
        class="flex w-full items-center gap-2.5 px-3 py-2.5 text-left hover:bg-surface-50"
      >
        <span class="flex-1 min-w-0">
          <span class="block text-sm font-semibold text-surface-800 truncate">{resolved_value(
            e,
            @resolved
          )}</span>
          <span class="block text-[11px] text-surface-500">
            Edit conflict for {field_label(e.conflict.field)} was auto-resolved
          </span>
        </span>
        <.icon name="hero-chevron-right" class="w-4 h-4 text-surface-300" />
      </button>

      <.delete_popup_row :for={d <- @dels} delete={d} subtitle="Edited expense deleted during sync" />
    </.popup_shell>
    """
  end

  # ── Popup building blocks ────────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :empty, :boolean, required: true
  slot :inner_block, required: true

  defp popup_shell(assigns) do
    ~H"""
    <div class="absolute right-6 top-14 z-40 w-80 rounded-lg border border-surface-200 bg-white shadow-xl overflow-hidden">
      <div class="flex items-center justify-between border-b border-surface-100 px-3 py-2">
        <span class="text-xs font-semibold text-surface-700">{@title}</span>
        <button
          :if={not @empty}
          phx-click="dismiss_all"
          class="text-[11px] font-medium text-primary-700 hover:underline"
        >
          Dismiss all
        </button>
      </div>
      <div class="max-h-[60vh] overflow-y-auto divide-y divide-surface-100">
        <p :if={@empty} class="px-3 py-4 text-center text-xs text-surface-400">Nothing to review.</p>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :delete, :map, required: true
  attr :subtitle, :string, required: true

  defp delete_popup_row(assigns) do
    ~H"""
    <div class="px-3 py-2.5">
      <div class="flex items-center gap-2.5">
        <.icon name="hero-trash" class="w-4 h-4 text-warning-600 shrink-0" />
        <span class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-surface-800 truncate">{@delete.description}</span>
          <span class="block text-[11px] text-surface-500">{@subtitle}</span>
        </span>
      </div>
      <div class="pl-6">
        <.delete_actions delete={@delete} />
      </div>
    </div>
    """
  end

  attr :delete, :map, required: true

  defp delete_actions(assigns) do
    ~H"""
    <div class="mt-2 flex items-center gap-2">
      <button
        phx-click="restore"
        phx-value-id={@delete.id}
        class="rounded-md bg-primary-800 px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-primary-900"
      >
        Restore
      </button>
      <button
        phx-click="dismiss_delete"
        phx-value-id={@delete.id}
        class="rounded-md px-2.5 py-1 text-[11px] font-medium text-surface-500 hover:bg-surface-100"
      >
        Keep deleted
      </button>
    </div>
    """
  end

  # ── Bell ─────────────────────────────────────────────────────────────────────

  attr :count, :integer, required: true

  defp conflict_bell(assigns) do
    ~H"""
    <button
      phx-click="toggle_inbox"
      class="relative inline-flex items-center justify-center rounded-md p-1.5 text-surface-600 hover:bg-surface-50"
      title="Changes needing review"
    >
      <.icon name="hero-bell" class="w-5 h-5" />
      <span
        :if={@count > 0}
        class="absolute -top-0.5 -right-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-warning-500 px-1 text-[10px] font-bold text-white"
      >
        {@count}
      </span>
    </button>
    """
  end

  # ── Expense list (clean rows — no conflict markers; row click opens editor) ───

  attr :expenses, :list, required: true
  attr :resolved, :map, required: true

  defp expense_rows(assigns) do
    ~H"""
    <button
      :for={e <- @expenses}
      type="button"
      phx-click="open_editor"
      phx-value-id={e.id}
      class="flex w-full items-center gap-4 px-4 py-3 bond-ink-hover-row transition-colors text-left cursor-pointer"
      style="--bond-ink: var(--color-primary-800)"
    >
      <span class="shrink-0 text-sm tabular-nums w-24 text-surface-600">{e.date_display}</span>
      <span class="flex-1 text-sm font-medium text-surface-800">{resolved_value(e, @resolved)}</span>
      <div class="flex items-center gap-1.5">
        <span
          :if={e.category}
          class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-surface-50 border border-surface-200 text-surface-800"
        >
          {e.category}
        </span>
      </div>
      <span class="shrink-0 text-sm font-bold tabular-nums w-16 text-right text-success-600">
        {resolved_amount(e, @resolved)}
      </span>
    </button>
    """
  end

  # ── Expense editor (side panel, Details + Conflicts tab) ─────────────────────

  attr :editor, :map, required: true
  attr :expenses, :list, required: true
  attr :resolved, :map, required: true

  defp expense_editor(assigns) do
    expense = Enum.find(assigns.expenses, &(&1.id == assigns.editor.id))
    # The tab holds unresolved conflicts only. Once the conflict is overridden or
    # dismissed the tab disappears, so a settled expense reads as an ordinary edit.
    unresolved = conflicting?(expense, assigns.resolved)
    on_conflicts = unresolved and assigns.editor.tab == :conflicts

    assigns =
      assign(assigns, expense: expense, unresolved: unresolved, on_conflicts: on_conflicts)

    ~H"""
    <Bond.side_panel id="expense-editor" title="Edit expense" on_close="close_editor">
      <%!-- Conflicts tab, present only while a conflict is unresolved --%>
      <div :if={@unresolved} class="mb-4 flex gap-1 border-b border-white/10">
        <.tab_button label="Details" active={@editor.tab == :details} tab="details" />
        <.tab_button label="Conflicts" active={@editor.tab == :conflicts} tab="conflicts" />
      </div>

      <%!-- Details form: shown unless the Conflicts tab is active --%>
      <div :if={not @on_conflicts} class="space-y-3">
        <.field label="Description" value={resolved_value(@expense, @resolved)} />
        <.field label="Amount" value={resolved_amount(@expense, @resolved)} />
        <.field label="Date" value={@expense.date_display} />
        <.field label="Category" value={@expense.category || "Uncategorized"} />
      </div>

      <%!-- Conflicts tab body --%>
      <div :if={@on_conflicts}>
        <.entity_history expense={@expense} />
      </div>

      <%!-- Save/Cancel belong to editing details; hide them on the Conflicts tab --%>
      <:footer :if={not @on_conflicts}>
        <button phx-click="close_editor" class="text-xs font-medium text-primary-300 hover:text-white">
          Cancel
        </button>
        <button
          phx-click="noop"
          class="rounded-md bg-white/15 px-3 py-1.5 text-xs font-semibold text-white hover:bg-white/25"
        >
          Save
        </button>
      </:footer>
    </Bond.side_panel>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :tab, :string, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="set_tab"
      phx-value-tab={@tab}
      class={[
        "border-b-2 px-3 py-2 text-sm font-medium transition-colors -mb-px",
        @active && "border-primary-400 text-white",
        not @active && "border-transparent text-primary-300 hover:text-white"
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp field(assigns) do
    ~H"""
    <div>
      <label class="block text-[11px] font-medium text-primary-300">{@label}</label>
      <input
        value={@value}
        readonly
        class="mt-1 w-full rounded-md border border-white/10 bg-white/5 px-2.5 py-1.5 text-sm text-white"
      />
    </div>
    """
  end

  # Per-entity conflict detail: the winner/loser change pair with an override.
  attr :expense, :map, required: true

  defp entity_history(assigns) do
    ~H"""
    <div class="text-white">
      <p class="mb-3 text-xs text-primary-300 leading-relaxed">
        The {field_label(@expense.conflict.field)} was edited on two devices at once. LocalCents kept one —
        pick the other to override it going forward, or dismiss to keep what was kept.
      </p>
      <ol class="space-y-0">
        <.history_entry
          badge="Kept"
          badge_class="bg-success-500/20 text-success-300"
          prov={@expense.conflict.winner}
          field={@expense.conflict.field}
          last={false}
        />
        <.history_entry
          badge="Dropped"
          badge_class="bg-white/10 text-primary-300"
          prov={@expense.conflict.loser}
          field={@expense.conflict.field}
          last={true}
        >
          <button
            phx-click="choose"
            phx-value-id={@expense.id}
            phx-value-value={@expense.conflict.loser.value}
            class="mt-2 rounded-md border border-white/20 bg-white/5 px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-white/10"
          >
            Make this the value
          </button>
        </.history_entry>
      </ol>

      <%!-- Per-entity dismiss: accept the kept value and clear this conflict, so a user
      grinding through many can make progress one at a time. --%>
      <div class="mt-1 flex items-center justify-between border-t border-white/10 pt-3">
        <span class="text-[11px] text-primary-300">Happy with what was kept?</span>
        <button
          phx-click="choose"
          phx-value-id={@expense.id}
          phx-value-value={@expense.conflict.winner.value}
          class="rounded-md bg-white/15 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-white/25"
        >
          Dismiss conflict
        </button>
      </div>
    </div>
    """
  end

  attr :badge, :string, required: true
  attr :badge_class, :string, required: true
  attr :prov, :map, required: true
  attr :field, :atom, required: true
  attr :last, :boolean, default: false
  slot :inner_block

  defp history_entry(assigns) do
    ~H"""
    <li class="relative pl-6 pb-5">
      <span :if={not @last} class="absolute left-[7px] top-4 bottom-0 w-px bg-white/15"></span>
      <span class="absolute left-0 top-1 flex h-3.5 w-3.5 items-center justify-center rounded-full border-2 border-primary-400 bg-primary-900"></span>
      <div class="flex items-center gap-2">
        <span class={[
          "rounded-full px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide",
          @badge_class
        ]}>
          {@badge}
        </span>
        <span class="text-[11px] text-primary-300">{field_label(@field)}</span>
      </div>
      <p class="mt-1 text-sm font-medium text-white">{@prov.value}</p>
      <p class="mt-0.5 text-[11px] text-primary-300">{@prov.device} · {@prov.at}</p>
      {render_slot(@inner_block)}
    </li>
    """
  end

  # ── Floating variant switcher (dev-only) ─────────────────────────────────────

  attr :variant, :string, required: true

  defp switcher(assigns) do
    assigns = assign(assigns, :label, variant_label(assigns.variant))

    ~H"""
    <div
      :if={Application.get_env(:local_cents, :env) != :prod}
      id="variant-switcher"
      phx-hook=".SwitcherKeys"
      class="fixed bottom-4 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-surface-700 bg-surface-900 px-1.5 py-1.5 text-white shadow-xl"
    >
      <button phx-click="cycle" phx-value-dir="prev" class="rounded-full p-1.5 hover:bg-white/10">
        <.icon name="hero-chevron-left" class="w-4 h-4" />
      </button>
      <span class="min-w-52 px-2 text-center text-xs font-semibold tabular-nums">{@label}</span>
      <button phx-click="cycle" phx-value-dir="next" class="rounded-full p-1.5 hover:bg-white/10">
        <.icon name="hero-chevron-right" class="w-4 h-4" />
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SwitcherKeys">
      export default {
        mounted() {
          this._onKeydown = (e) => {
            const t = e.target
            if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return
            if (e.key === "ArrowLeft") { e.preventDefault(); this.pushEvent("cycle", {dir: "prev"}) }
            if (e.key === "ArrowRight") { e.preventDefault(); this.pushEvent("cycle", {dir: "next"}) }
          }
          window.addEventListener("keydown", this._onKeydown)
        },
        destroyed() { window.removeEventListener("keydown", this._onKeydown) }
      }
    </script>
    """
  end

  defp variant_label("a"), do: "A — Grouped by action"
  defp variant_label("b"), do: "B — Activity feed"
  defp variant_label("c"), do: "C — Compact"

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp assign_conflict_lists(assigns) do
    assigns
    |> assign(:scalars, unresolved_scalars(assigns.expenses, assigns.resolved))
    |> assign(:dels, pending_deletes(assigns.deletes, assigns.delete_status))
  end

  defp field_label(:cost), do: "amount"
  defp field_label(:description), do: "description"
  defp field_label(field), do: to_string(field)

  defp conflicting?(%{conflict: nil}, _resolved), do: false
  defp conflicting?(%{id: id}, resolved), do: not Map.has_key?(resolved, id)

  defp resolved_value(%{conflict: %{field: :description}} = e, resolved),
    do: Map.get(resolved, e.id, e.description)

  defp resolved_value(e, _resolved), do: e.description

  defp resolved_amount(%{conflict: %{field: :cost}} = e, resolved),
    do: Map.get(resolved, e.id, e.amount_display)

  defp resolved_amount(e, _resolved), do: e.amount_display

  defp unresolved_scalars(expenses, resolved),
    do: Enum.filter(expenses, &conflicting?(&1, resolved))

  defp pending_deletes(deletes, status),
    do: Enum.reject(deletes, &Map.has_key?(status, &1.id))

  defp notif_count(assigns) do
    length(unresolved_scalars(assigns.expenses, assigns.resolved)) +
      length(pending_deletes(assigns.deletes, assigns.delete_status))
  end
end
