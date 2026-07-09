defmodule LocalCentsWeb.Bond.Layouts.Modal do
  @moduledoc """
  A centered, dismissible dialog floating over a dimmed backdrop.

  Where `LocalCentsWeb.Bond.Layouts.SidePanel` slides an editor in from the edge,
  Modal is the small, focused interruption — a rename field, a delete
  confirmation — that owns the screen until the user resolves it. It is meant to
  feel like a native macOS sheet rather than a browser `window.confirm`.

  ## Rendering and closing

  The component has no open/closed state of its own: the caller renders it only
  while it should be shown (typically guarded by an assign) and removes it to
  dismiss. Three paths push the caller's `on_cancel` event — clicking the
  backdrop, the × button, or pressing Escape (wired by a colocated hook) — so the
  caller decides what dismissal means.

  The panel is a `<dialog open>` for its semantic `role="dialog"`; `open` shows it
  without a JS `showModal()` call, keeping it in the normal document flow rather
  than the browser's top layer.

  ## Slots

  `inner_block` is the body — for a form-driven modal (e.g. rename) put the whole
  `<form>`, including its submit button, here so the button stays inside the form.
  `actions` is an optional right-aligned footer for plain buttons (e.g. a delete
  confirmation's Cancel/Delete), separated from the body by a divider.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, required: true, doc: "DOM id for the outer wrapper; required by the JS hook"
  attr :title, :string, required: true, doc: "Heading shown in the modal's title bar"

  attr :on_cancel, :string,
    required: true,
    doc: "LiveView event pushed when the backdrop, × button, or Escape dismisses the modal"

  attr :rest, :global, doc: "Additional HTML attributes on the outer wrapping div"

  slot :inner_block, required: true, doc: "Modal body; hold a whole form here when form-driven"

  slot :actions,
    doc: "Optional right-aligned footer for plain action buttons; omit to show no footer"

  @spec modal(Socket.assigns()) :: Rendered.t()
  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-hook=".ModalKeys"
      data-on-cancel={@on_cancel}
      {@rest}
    >
      <%!-- Backdrop — clicking it dismisses the modal --%>
      <div
        class="absolute inset-0"
        phx-click={@on_cancel}
        aria-hidden="true"
        style="background: color-mix(in srgb, var(--color-surface-950) 45%, transparent)"
      >
      </div>
      <%!-- Panel — <dialog open> for a semantic role without a JS showModal() call --%>
      <dialog
        open
        aria-modal="true"
        class="relative w-full max-w-sm rounded-xl overflow-hidden bg-surface-50"
        style="border: 1px solid var(--color-surface-400); box-shadow: 0 20px 25px -5px color-mix(in srgb, var(--color-primary-800) 25%, transparent)"
      >
        <div class="flex items-center justify-between px-5 pt-4 pb-3 border-b border-surface-200">
          <h2 class="text-base font-bold tracking-wide text-surface-800">{@title}</h2>
          <button
            type="button"
            phx-click={@on_cancel}
            aria-label="Close"
            class="text-surface-500 hover:text-primary-800 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
        <div class="px-5 py-4">
          {render_slot(@inner_block)}
        </div>
        <div
          :if={@actions != []}
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-surface-200 bg-surface-100"
        >
          {render_slot(@actions)}
        </div>
      </dialog>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ModalKeys">
      export default {
        mounted() {
          // Focus the first field so a keyboard user can act immediately (native feel).
          const field = this.el.querySelector("input, textarea, select")
          if (field) field.focus()
          this._onKeydown = (e) => {
            if (e.key === "Escape") {
              e.preventDefault()
              this.pushEvent(this.el.dataset.onCancel)
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
