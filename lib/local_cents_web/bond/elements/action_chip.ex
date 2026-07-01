defmodule LocalCentsWeb.Bond.Elements.ActionChip do
  @moduledoc "A compact pill-shaped button with a trailing chevron, used to trigger dropdowns or menus."

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :label, :string, required: true, doc: "The chip label text"

  attr :rest, :global,
    doc: "HTML attributes passed through to the button element (e.g. phx-click)"

  @spec action_chip(Socket.assigns()) :: Rendered.t()
  def action_chip(assigns) do
    ~H"""
    <button
      class="flex items-center gap-1 px-2.5 py-1.5 text-sm font-semibold bond-ink-text bond-ink-hover-soft rounded-full transition-colors"
      style="--bond-ink: var(--color-primary-800)"
      {@rest}
    >
      {@label}
      <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
    </button>
    """
  end
end
