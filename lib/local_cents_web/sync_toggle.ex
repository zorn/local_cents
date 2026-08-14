defmodule LocalCentsWeb.SyncToggle do
  @moduledoc """
  The `on_mount` hook that wires the Mac-side offline toggle into every window.

  The toggle suspends and resumes the sync link on cue, forcing the two peers to diverge
  during a live or recorded demo (see [ADR 0025](0025-two-peer-sync-architecture.html)).
  It is a developer affordance, not product surface, so it shows only on the desktop
  client and only when a sync link actually exists — `LocalCentsWeb.Sync.PeerClient`'s
  `link_state/0` returns `nil` on any instance with no peer configured, which hides it.

  Attached once in `LocalCentsWeb.live_view/0`, after `LocalCentsWeb.Client` so `@client`
  is already assigned. It does two things for every view:

    * assigns `:sync_link` (`:online`, `:offline`, or `nil`) so `LocalCentsWeb.Layouts`
      can render `Bond.offline_toggle/1` and point it the right way;
    * attaches a `handle_event/3` hook so the toggle's `toggle_sync_link` click is
      handled in this one place rather than repeated in each of the four LiveViews.

  The click asks `PeerClient` to flip the link, then re-reads the state so the control
  reflects what actually happened. Reading back rather than assuming keeps the button
  honest even if the link never came up.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias LocalCentsWeb.Sync.PeerClient
  alias Phoenix.LiveView.Socket

  @spec on_mount(:default, params :: map(), session :: map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign_sync_link()
      |> attach_hook(:sync_toggle, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  # Only the desktop client offers the toggle; a browser tab is the always-online peer
  # and never goes offline (ADR 0025), so it always reads `nil` and shows nothing.
  defp assign_sync_link(socket) do
    state = if socket.assigns.client == :desktop, do: PeerClient.link_state(), else: nil
    assign(socket, :sync_link, state)
  end

  defp handle_event("toggle_sync_link", _params, socket) do
    PeerClient.toggle_link()
    {:halt, assign_sync_link(socket)}
  end

  # Every other event belongs to the view itself.
  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
