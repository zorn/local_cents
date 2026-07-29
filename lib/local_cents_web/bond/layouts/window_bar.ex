defmodule LocalCentsWeb.Bond.Layouts.WindowBar do
  @moduledoc """
  The window's draggable title strip: a marbled endpaper bar with the window's
  title centered in white over the native traffic lights.

  Paired with the transparent macOS title bar the shell builds each window with
  (see [ADR 0013](0013-transparent-native-title-bar.html)): the native title text
  is hidden and the native title bar is transparent, so this `bond-marble` strip
  shows through as the visible title bar (matching the `desktop_window` mock) with
  the real red/amber/green traffic lights sitting on it. It is
  `data-tauri-drag-region`, making the strip drag the native window, and a
  fixed-height flex child, so the content it sits above is reserved clear of the
  traffic lights. The title is decorative chrome — the page keeps its own semantic
  heading — so it is hidden from assistive tech.

  The title dims when the window is in the background, matching how macOS — and the
  native traffic lights — treat a background window. `app.js` toggles a
  `.window-inactive` class on `<html>` from the WKWebView's window focus/blur, which
  the `.bond-window-title` rule in `bond.css` keys off.

  In the `:browser` client the same strip is drawn without the drag region, which is
  inert there, and the leading space the traffic lights would occupy carries a back
  link to the library instead (see
  [ADR 0023](0023-browser-as-a-second-client.html)) — the app's one window-level
  destination, so the label is fixed rather than an attribute. That link is
  the *window-level* way out — "leave this Book" — and is distinct from the in-page
  back link the secondary views draw for "leave this sub-view"; on those pages the two
  together read as a breadcrumb.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, default: nil, doc: "Text shown centered in the bar; omitted when nil"

  attr :client, :atom,
    required: true,
    values: [:desktop, :browser],
    doc: "Which client the bar is drawn in; `:browser` drops the native-only drag region"

  attr :back_path, :string,
    default: nil,
    doc: "When set, a back link is shown at the leading edge; ignored in the `:desktop` client"

  @spec window_bar(Socket.assigns()) :: Rendered.t()
  def window_bar(assigns) do
    ~H"""
    <div
      data-tauri-drag-region={@client == :desktop}
      class="bond-marble relative flex h-7 shrink-0 select-none items-center justify-center border-b border-surface-950"
    >
      <%!-- The leading slot the traffic lights occupy in a native window is free in a
      browser, so that is where the way back goes. It is absolutely positioned so the
      title stays centered on the bar rather than on the space left over beside it. --%>
      <.link
        :if={@client == :browser and @back_path}
        navigate={@back_path}
        class="absolute left-2 inline-flex items-center gap-0.5 text-xs font-semibold text-white/80 transition-colors hover:text-white"
      >
        <.icon name="hero-chevron-left" class="h-3 w-3" />Library
      </.link>

      <span
        :if={@title}
        aria-hidden="true"
        class="bond-window-title pointer-events-none text-sm font-semibold text-white/90"
      >
        {@title}
      </span>
    </div>
    """
  end
end
