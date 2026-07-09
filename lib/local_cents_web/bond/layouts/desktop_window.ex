defmodule LocalCentsWeb.Bond.Layouts.DesktopWindow do
  @moduledoc """
  A macOS-style desktop window chrome with a marbled title bar and subtly textured background.

  Renders traffic-light buttons and a centered title above slot content.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, required: true, doc: "Text displayed centered in the title bar"

  slot :inner_block, required: true, doc: "Content rendered below the title bar"

  @spec desktop_window(Socket.assigns()) :: Rendered.t()
  def desktop_window(assigns) do
    ~H"""
    <div
      class="bond-window-paper rounded-xl overflow-hidden shadow-lg"
      style="border: 1px solid var(--color-surface-400); box-shadow: 0 10px 15px -3px color-mix(in srgb, var(--color-primary-800) 20%, transparent); --bond-ink: var(--color-primary-800); --bond-ink-strong: var(--color-primary-900)"
    >
      <div
        class="bond-marble relative flex items-center pl-3 pr-4 py-2 select-none"
        style="border-bottom: 1px solid var(--color-surface-950)"
      >
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full border border-black/20 bg-mac-os-close"></button>
          <button class="w-3 h-3 rounded-full border border-black/20 bg-mac-os-minimize"></button>
          <button class="w-3 h-3 rounded-full border border-black/20 bg-mac-os-maximize"></button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-white/90 pointer-events-none">
          {@title}
        </span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
