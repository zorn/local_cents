defmodule LocalCentsWeb.Bond.Elements.Menu do
  @moduledoc """
  A dropdown menu that opens from a trigger and floats above everything else.

  The menu exists to solve a specific problem: a row's overflow menu lives inside
  the scrolling, `overflow`-clipped list card, so an absolutely-positioned panel
  gets cut off. This component's panel is `position: fixed` and positioned by a
  colocated JS hook, so it escapes every `overflow` ancestor and draws on the top
  layer regardless of where the trigger sits.

  The hook also gives it desktop-menu manners:

    * **Flips** below the trigger when there's room, above it when there isn't.
    * **Clamps** horizontally so it never spills past the window's left/right edge.
    * **Closes** on outside click, Escape, and on window resize or scroll (the
      trigger has moved, so the menu dismisses — matching native apps).

  Open/close and positioning are entirely client-side; the menu items inside are
  the caller's, so their `phx-click`s drive the server as usual. Selecting an item
  also closes the menu.

  ## Slots

  `trigger` is the control that opens the menu (give it its own accessible name,
  e.g. an icon button with an `sr-only` label). `inner_block` is the menu items —
  typically full-width `<button>`s.

  ## Example

      <Bond.menu id={"menu-\#{@book.id}"}>
        <:trigger>
          <Bond.button variant={:square}>
            <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
            <span class="sr-only">Book actions</span>
          </Bond.button>
        </:trigger>
        <button phx-click="rename" phx-value-id={@book.id} class="...">Rename</button>
        <button phx-click="delete" phx-value-id={@book.id} class="...">Delete</button>
      </Bond.menu>
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string,
    required: true,
    doc: "DOM id for the wrapper; required by the positioning hook"

  attr :rest, :global, doc: "HTML attributes passed through to the wrapper element"

  slot :trigger, required: true, doc: "The control that opens the menu; carries its own label"
  slot :inner_block, required: true, doc: "Menu items, typically full-width buttons"

  @spec menu(Socket.assigns()) :: Rendered.t()
  def menu(assigns) do
    ~H"""
    <div id={@id} class="relative inline-flex" phx-hook=".Menu" {@rest}>
      <div data-menu-trigger class="inline-flex">
        {render_slot(@trigger)}
      </div>
      <div
        data-menu-panel
        role="menu"
        class="invisible fixed z-50 min-w-[9rem] rounded-lg bg-surface-50 py-1 shadow-lg"
        style="border: 1px solid var(--color-surface-300)"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Menu">
      export default {
        mounted() {
          const wrapper = this.el.querySelector("[data-menu-trigger]")
          this.panel = this.el.querySelector("[data-menu-panel]")
          // ARIA and the click handler belong on the real control (the button/link
          // the user focuses), not the wrapper, so assistive tech announces the
          // menu's expanded state. Fall back to the wrapper if there isn't one.
          this.control = wrapper.querySelector("button, a, [role='button']") || wrapper
          this.control.setAttribute("aria-haspopup", "true")
          this.control.setAttribute("aria-expanded", "false")

          this.onTrigger = (e) => { e.stopPropagation(); this.toggle() }
          this.onPanelClick = () => this.close()
          this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close() }
          this.onKeydown = (e) => { if (e.key === "Escape") this.close() }
          this.onReflow = () => this.close()

          this.control.addEventListener("click", this.onTrigger)
          this.panel.addEventListener("click", this.onPanelClick)
        },

        destroyed() {
          this.detachOpenListeners()
          this.control.removeEventListener("click", this.onTrigger)
          this.panel.removeEventListener("click", this.onPanelClick)
        },

        toggle() {
          this.panel.classList.contains("invisible") ? this.open() : this.close()
        },

        open() {
          this.position()
          this.panel.classList.remove("invisible")
          this.control.setAttribute("aria-expanded", "true")
          document.addEventListener("click", this.onDocClick)
          document.addEventListener("keydown", this.onKeydown)
          window.addEventListener("resize", this.onReflow)
          window.addEventListener("scroll", this.onReflow, true)
        },

        close() {
          this.panel.classList.add("invisible")
          this.control.setAttribute("aria-expanded", "false")
          this.detachOpenListeners()
        },

        detachOpenListeners() {
          document.removeEventListener("click", this.onDocClick)
          document.removeEventListener("keydown", this.onKeydown)
          window.removeEventListener("resize", this.onReflow)
          window.removeEventListener("scroll", this.onReflow, true)
        },

        // Place the panel relative to the trigger in viewport coordinates: below if
        // it fits, otherwise above; right-aligned to the trigger, clamped so it
        // never leaves the window on either edge.
        position() {
          const t = this.control.getBoundingClientRect()
          const pw = this.panel.offsetWidth
          const ph = this.panel.offsetHeight
          const gap = 4
          const margin = 8

          let top = t.bottom + gap
          if (top + ph > window.innerHeight - margin) {
            const above = t.top - gap - ph
            top = above >= margin ? above : Math.max(margin, window.innerHeight - margin - ph)
          }

          let left = t.right - pw
          left = Math.min(Math.max(left, margin), window.innerWidth - margin - pw)

          this.panel.style.top = `${top}px`
          this.panel.style.left = `${left}px`
        }
      }
    </script>
    """
  end
end
