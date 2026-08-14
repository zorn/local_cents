defmodule LocalCentsWeb.Bond.Layouts.OfflineToggle do
  @moduledoc """
  A floating pill that suspends and resumes the Mac-side sync link on cue — the control
  that forces divergence during a live or recorded demo (see
  [ADR 0025](0025-two-peer-sync-architecture.html)).

  Like the `LocalCentsWeb.Bond.Layouts.DebugBar` it is a developer affordance, not part
  of the product surface: `LocalCentsWeb.Layouts` decides when it shows (the desktop
  client, and only when a sync link exists), and this component only draws the state it
  is handed. It floats in the corner rather than taking a slice of the layout, so no
  screen has to make room for it.

  It renders the current state, not just an action: online is the quiet resting look;
  offline is tinted amber so the operator can see at a glance that the app is holding
  edits back. A click emits `toggle_sync_link`, handled once for every window by
  `LocalCentsWeb.SyncToggle`.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :online, :boolean,
    required: true,
    doc: "Whether the link is currently live; drives both the label and the offline tint"

  @spec offline_toggle(Socket.assigns()) :: Rendered.t()
  def offline_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_sync_link"
      class={[
        "bond-marble bond-stamp fixed bottom-3 right-3 z-40 flex items-center gap-1.5",
        "rounded px-2.5 py-1 text-xs font-semibold text-white/90 transition-colors hover:text-white"
      ]}
      style={toggle_style(@online)}
    >
      <.icon name={if @online, do: "hero-signal", else: "hero-signal-slash"} class="h-4 w-4" />
      {if @online, do: "Take Offline", else: "Come Online"}
    </button>
    """
  end

  # Amber while offline so the abnormal, edits-are-diverging state reads at a glance; the
  # neutral surface stamp while online keeps the resting control quiet.
  defp toggle_style(online) do
    shadow = "--bond-stamp-shadow: var(--color-surface-950)"
    if online, do: shadow, else: shadow <> "; background: var(--color-warning-700); color: white"
  end
end
