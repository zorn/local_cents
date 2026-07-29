defmodule LocalCentsWeb.Bond.Layouts.DebugBar do
  @moduledoc """
  A collapsed pill in the corner of the viewport that expands into a row of developer
  links.

  Shown only when the app is being driven from a browser during development (see
  [ADR 0023](0023-browser-as-a-second-client.html)) — `LocalCentsWeb.Layouts` decides,
  this component only draws what it is handed. It floats over the page rather than
  taking a slice of the layout, so no screen has to make room for it; collapsing to a
  single pill is what keeps that from covering anything that matters, like the
  library's create bar.

  Built on `<details>` rather than a click handler so it toggles without JavaScript:
  it works on the disconnected first render and is keyboard-operable for free. The
  link row is positioned beside the pill instead of laying the `<details>` out as a
  flex row, because `display: flex` on `<details>` is not reliably honored across
  engines when the element is closed.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :links, :list,
    required: true,
    doc: """
    Links to show, each a map with a `:label` and an `:href`
    """

  attr :open, :boolean,
    default: false,
    doc: "Whether the pill starts expanded; the user toggles it from there"

  @spec debug_bar(Socket.assigns()) :: Rendered.t()
  def debug_bar(assigns) do
    ~H"""
    <details open={@open} class="bond-debug-bar fixed bottom-3 right-3 z-40">
      <summary
        class="bond-marble bond-stamp flex h-8 w-8 cursor-pointer items-center justify-center rounded text-white/90 transition-colors hover:text-white"
        style="--bond-stamp-shadow: var(--color-surface-950)"
      >
        <.icon name="hero-wrench-screwdriver" class="h-4 w-4" />
        <span class="sr-only">Developer links</span>
      </summary>

      <%!-- Anchored to the pill's left rather than below it: the pill sits at the
      bottom of the viewport, so anything expanding downward would open off-screen. --%>
      <nav
        aria-label="Developer links"
        class="absolute bottom-0 right-10 flex items-center gap-2 whitespace-nowrap"
      >
        <a
          :for={link <- @links}
          href={link.href}
          target="_blank"
          rel="noopener"
          class="bond-marble bond-stamp rounded px-2.5 py-1 text-xs font-semibold text-white/90 transition-colors hover:text-white"
          style="--bond-stamp-shadow: var(--color-surface-950)"
        >
          {link.label}
        </a>
      </nav>
    </details>
    """
  end
end
