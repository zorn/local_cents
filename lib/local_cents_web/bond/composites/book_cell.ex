defmodule LocalCentsWeb.Bond.Composites.BookCell do
  @moduledoc "A book row for use inside `LocalCentsWeb.Bond.Elements.ListView`."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :name, :string, required: true, doc: "Book title displayed as the primary text"

  attr :last_updated, :string,
    default: nil,
    doc: "Optional subtitle showing when the book was last updated; omit to render no subtitle"

  attr :rest, :global, doc: "HTML attributes passed through to the row element (e.g. phx-click)"

  slot :actions,
    doc: "Trailing controls for the row (e.g. an overflow menu and an Open button)"

  @spec book_cell(Socket.assigns()) :: Rendered.t()
  def book_cell(assigns) do
    ~H"""
    <div
      class="flex items-center gap-4 px-4 py-4 bond-ink-hover-row transition-colors"
      style="--bond-ink: var(--color-primary-800)"
      {@rest}
    >
      <div class="flex-1 min-w-0">
        <p class="truncate text-base font-semibold leading-snug text-surface-800">
          {@name}
        </p>
        <p :if={@last_updated} class="text-xs mt-0.5 text-surface-600">
          Last Updated: {@last_updated}
        </p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
