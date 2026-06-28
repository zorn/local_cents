defmodule Bond.Layouts.SidePanel do
  @moduledoc """
  A right-aligned slide-in panel with a dimmed overlay backdrop.

  ## Visual structure

  When rendered, the component fills its entire containing element with two side-by-side regions:

  - **Dim overlay** (left, flexible width) — a semi-transparent dark wash over whatever content
    sits behind the panel. Clicking it fires the close event.
  - **Panel** (right, fixed 20rem / `w-80`) — a dark denim-gradient drawer containing a header,
    a scrollable body, and an optional footer action row.

  ## How it is scoped

  The outer wrapper uses `position: absolute; inset: 0` (covering all four edges), which means
  it positions itself relative to the **nearest ancestor element that has `position: relative`
  (or `absolute`/`fixed`/`sticky`)**. It does NOT cover the full browser viewport. The caller is
  responsible for ensuring such an ancestor exists in the DOM — typically a content area wrapper
  with `class="relative overflow-hidden"`.

  This is intentional: the panel should feel like it slides in over the content beneath it, not
  over the whole application shell (title bar, navigation, etc.).

  ## The `<dialog>` element

  The panel itself is rendered as a `<dialog open>` HTML element. This gives the component a
  meaningful semantic role (`role="dialog"`) that assistive technologies like screen readers can
  announce. The `open` attribute makes it visible without needing JavaScript to call
  `dialog.showModal()`. Using the non-modal form keeps the panel scoped to its container rather
  than breaking out to the browser's top layer.

  ## Closing the panel

  Three paths can close the panel, all of which push `on_close` to the server:

  1. Clicking the dim overlay on the left
  2. Clicking the × button in the panel header
  3. Pressing the Escape key (handled via a `window` keydown listener in the JS hook)

  All three paths are disabled when `locked={true}`, which is intended for use when a form
  inside the panel has unsaved changes and you want to prevent accidental data loss.

  ## Requirements

  - The caller **must** provide an `id` attribute — it is required by the `phx-hook` that wires
    up the Escape key listener.
  - The caller **must** wrap the component in a `position: relative; overflow: hidden` ancestor
    so the `absolute inset-0` positioning is scoped correctly.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, required: true, doc: "Heading shown in the panel header"

  attr :on_close, :string,
    required: true,
    doc: "LiveView event name fired when the overlay, close button, or Escape is triggered"

  attr :locked, :boolean,
    default: false,
    doc: "When true all close paths are disabled; use this to guard an unsaved (dirty) form"

  attr :id, :string,
    required: true,
    doc: "DOM id for the outer wrapper; required by the JS hook"

  attr :rest, :global, doc: "Additional HTML attributes on the outer wrapping div"

  slot :inner_block, required: true, doc: "Scrollable body content"
  slot :footer, doc: "Action row rendered below the body; omit to show no footer"

  @spec side_panel(Socket.assigns()) :: Rendered.t()
  def side_panel(assigns) do
    ~H"""
    <div
      id={@id}
      class="absolute inset-0 flex"
      phx-hook=".SidePanel"
      data-on-close={@on_close}
      data-locked={"#{@locked}"}
      {@rest}
    >
      <%!-- Dim overlay — clicking closes the panel unless locked --%>
      <div
        class="flex-1"
        phx-click={if !@locked, do: @on_close}
        style={"background: color-mix(in srgb, #{Bond.Tokens.color(:title_bar_border)} 50%, transparent)"}
      >
      </div>
      <%!-- Panel — <dialog open> for semantic HTML; non-modal so it stays scoped to the container --%>
      <dialog
        open
        class="bond-side-panel nb-denim flex flex-col shadow-2xl"
        style={"border-left: 1px solid #{Bond.Tokens.color(:title_bar_border)}"}
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-5 pt-4 pb-3 border-b border-white/10">
          <p class="font-nunito text-base font-bold text-white tracking-wide">{@title}</p>
          <button
            phx-click={if !@locked, do: @on_close}
            class="transition-colors"
            style={"color: #{Bond.Tokens.color(if @locked, do: :content_secondary, else: :accent_light)}"}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
        <%!-- Body --%>
        <div class="px-5 py-3 flex-1 overflow-y-auto">
          {render_slot(@inner_block)}
        </div>
        <%!-- Footer --%>
        <%= if @footer != [] do %>
          <div class="flex items-center justify-between px-6 py-4 border-t border-white/10">
            {render_slot(@footer)}
          </div>
        <% end %>
      </dialog>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SidePanel">
      export default {
        mounted() {
          this._onKeydown = (e) => {
            if (e.key === "Escape" && this.el.dataset.locked !== "true") {
              e.preventDefault()
              this.pushEvent(this.el.dataset.onClose)
            }
          }
          window.addEventListener("keydown", this._onKeydown)
        },
        destroyed() {
          window.removeEventListener("keydown", this._onKeydown)
        }
      }
    </script>
    """
  end
end
