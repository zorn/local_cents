defmodule LocalCentsWeb.Bond.Composites.ExpenseCell do
  @moduledoc "A notebook-themed expense row displaying date, description, tags, and amount."

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :date, :string, required: true, doc: "The expense date"
  attr :description, :string, required: true, doc: "The expense description"
  attr :amount, :string, required: true, doc: "The formatted expense amount"

  attr :tags, :list,
    default: [],
    doc: "List of %{label: string, color: string} maps; caller resolves color per label"

  attr :rest, :global, doc: "HTML attributes passed through to the row element (e.g. phx-click)"

  @spec expense_cell(Socket.assigns()) :: Rendered.t()
  def expense_cell(assigns) do
    ~H"""
    <div
      class="flex items-center gap-4 px-4 py-3 nb-t-hover-row transition-colors cursor-pointer"
      style="--nb-t: var(--color-primary-800)"
      {@rest}
    >
      <span class="shrink-0 text-sm tabular-nums w-24 text-surface-600">
        {@date}
      </span>
      <span class="flex-1 text-sm font-medium text-surface-800">
        {@description}
      </span>
      <div class="flex items-center gap-1.5">
        <%= for tag <- @tags do %>
          <Bond.Elements.TagPill.tag_pill label={tag.label} color={tag.color} />
        <% end %>
      </div>
      <span class="shrink-0 text-sm font-bold tabular-nums w-16 text-right text-success-600">
        {@amount}
      </span>
    </div>
    """
  end
end
