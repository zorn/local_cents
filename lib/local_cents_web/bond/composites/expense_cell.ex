defmodule LocalCentsWeb.Bond.Composites.ExpenseCell do
  @moduledoc "An expense row displaying date, description, an optional category, and amount."

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :date, :string, required: true, doc: "The formatted expense date"
  attr :description, :string, required: true, doc: "The expense description"
  attr :amount, :string, required: true, doc: "The formatted expense amount"

  attr :category, :map,
    default: nil,
    doc:
      "The expense's single category as %{label: string, color: string}, or nil when Uncategorized (LocalCents uses one Category per Expense, not tags — see ADR 0005)"

  attr :rest, :global, doc: "HTML attributes passed through to the row element (e.g. phx-click)"

  @spec expense_cell(Socket.assigns()) :: Rendered.t()
  def expense_cell(assigns) do
    ~H"""
    <div
      class="flex items-center gap-4 px-4 py-3 bond-ink-hover-row transition-colors cursor-pointer"
      style="--bond-ink: var(--color-primary-800)"
      role="button"
      tabindex="0"
      {@rest}
    >
      <span class="shrink-0 text-sm tabular-nums w-24 text-surface-600">
        {@date}
      </span>
      <span class="flex-1 text-sm font-medium text-surface-800">
        {@description}
      </span>
      <div class="flex items-center gap-1.5">
        <Bond.Elements.TagPill.tag_pill
          :if={@category}
          label={@category.label}
          color={@category.color}
        />
      </div>
      <span class="shrink-0 text-sm font-bold tabular-nums w-16 text-right text-success-600">
        {@amount}
      </span>
    </div>
    """
  end
end
