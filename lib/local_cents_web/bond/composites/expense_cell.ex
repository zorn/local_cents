defmodule LocalCentsWeb.Bond.Composites.ExpenseCell do
  @moduledoc "An expense row displaying date, description, an optional category, and amount."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :date_display, :string, required: true, doc: "The formatted expense date"
  attr :description, :string, required: true, doc: "The expense description"
  attr :amount_display, :string, required: true, doc: "The formatted expense amount"

  attr :category, :map,
    default: nil,
    doc:
      "The expense's single category as %{label: string, color: string}, or nil when Uncategorized"

  attr :rest, :global, doc: "HTML attributes passed through to the row element (e.g. phx-click)"

  @spec expense_cell(Socket.assigns()) :: Rendered.t()
  def expense_cell(assigns) do
    ~H"""
    <%!-- A real <button> (not a clickable <div>) so each row is reachable and
    activatable by keyboard and assistive tech, not just the mouse. --%>
    <button
      type="button"
      class="flex w-full items-center gap-4 px-4 py-3 bond-ink-hover-row transition-colors text-left cursor-pointer"
      style="--bond-ink: var(--color-primary-800)"
      {@rest}
    >
      <span class="shrink-0 text-sm tabular-nums w-24 text-surface-600">
        {@date_display}
      </span>
      <span class="flex-1 text-sm font-medium text-surface-800">
        {@description}
      </span>
      <div class="flex items-center gap-1.5">
        <span
          :if={@category}
          class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-surface-50 border border-surface-200 text-surface-800"
        >
          <span class="w-2 h-2 rounded-full shrink-0" style={"background: #{@category.color}"}></span>
          {@category.label}
        </span>
      </div>
      <span class="shrink-0 text-sm font-bold tabular-nums w-16 text-right text-success-600">
        {@amount_display}
      </span>
    </button>
    """
  end
end
