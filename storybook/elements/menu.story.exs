defmodule Storybook.Elements.Menu do
  use LocalCentsWeb.Storybook.Story, :example

  def doc do
    """
    A dropdown menu whose panel floats on the top layer (position: fixed), so it escapes any
    overflow-clipped container. It flips above the trigger when there's no room below, clamps
    to the window's left/right edges, and closes on outside-click, Escape, resize, or scroll.
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, assign(socket, picked: nil)}

  @impl Phoenix.LiveView
  def handle_event("pick", %{"choice" => choice}, socket),
    do: {:noreply, assign(socket, :picked, choice)}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="font-sans">
      <p class="text-xs text-surface-500 mb-2">
        The right-hand trigger sits near the window edge — its menu clamps so it never spills off.
        Shrink the browser window so a trigger is near the bottom to watch the menu flip upward.
        Clicking outside, pressing Escape, resizing, or scrolling closes it.
      </p>
      <p :if={@picked} class="text-xs font-semibold text-primary-800 mb-2">
        You picked: {@picked}
      </p>

      <%!-- overflow-hidden proves the fixed panel escapes a clipping ancestor --%>
      <div class="flex items-center justify-between overflow-hidden rounded-lg border border-surface-300 bg-surface-100 p-4">
        <.demo_menu id="menu-left" />
        <.demo_menu id="menu-center" />
        <.demo_menu id="menu-right" />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  defp demo_menu(assigns) do
    ~H"""
    <Bond.menu id={@id}>
      <:trigger>
        <Bond.button variant={:square}>
          <LocalCentsWeb.CoreComponents.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
          <span class="sr-only">Open menu</span>
        </Bond.button>
      </:trigger>
      <button
        type="button"
        role="menuitem"
        phx-click="pick"
        phx-value-choice="Rename"
        class="block w-full px-3 py-1.5 text-left text-sm text-surface-700 hover:bg-surface-100"
      >
        Rename
      </button>
      <button
        type="button"
        role="menuitem"
        phx-click="pick"
        phx-value-choice="Duplicate"
        class="block w-full px-3 py-1.5 text-left text-sm text-surface-700 hover:bg-surface-100"
      >
        Duplicate
      </button>
      <button
        type="button"
        role="menuitem"
        phx-click="pick"
        phx-value-choice="Delete"
        class="block w-full px-3 py-1.5 text-left text-sm hover:bg-surface-100"
        style="color: var(--color-error-600)"
      >
        Delete
      </button>
    </Bond.menu>
    """
  end
end
