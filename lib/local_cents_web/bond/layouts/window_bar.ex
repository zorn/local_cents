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
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, default: nil, doc: "Text shown centered in the bar; omitted when nil"

  @spec window_bar(Socket.assigns()) :: Rendered.t()
  def window_bar(assigns) do
    ~H"""
    <div
      data-tauri-drag-region
      class="bond-marble flex h-7 shrink-0 select-none items-center justify-center border-b border-surface-950"
    >
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
