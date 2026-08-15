defmodule LocalCentsWeb.WindowTitle do
  @moduledoc """
  Marks every open window `(Offline)` while the operator has the sync link suspended.

  During the two-peer Sync Demo the Mac side can go offline ([ADR 0025](0025-two-peer-sync-architecture.html)),
  but nothing in a window shows which state the app is in. This hook makes that state
  visible where it is always on screen: the window title. While the link is suspended a
  Book window titled `Sync Demo` reads `Sync Demo (Offline)`, and the Library window
  reads `Library (Offline)`; the plain title returns the moment the link comes back.

  The marker tracks the operator's *intent*, which `LocalCentsWeb.Sync.PeerClient.link_state/0`
  reports as `:online | :offline | nil`. Only the deliberate `:offline` state gets the
  suffix — an online link and a solo app with no peer (`nil`) both read plain — so the
  marker only ever appears when the operator flips the toggle.

  It is a universal `on_mount` hook attached in `LocalCentsWeb.live_view/0`, so offline
  is an app-level state every window mirrors rather than a per-window one that a second
  window could contradict. On mount it seeds the state from `link_state/0` and subscribes
  to the link's changes; the `{:sync_link, state}` broadcast fires only on a user flip
  (never for `nil` or a transient reconnect), so a window opened while already offline
  must seed itself rather than wait for a broadcast that will not come.

  Views set their title through `put_title/2` rather than assigning `page_title`
  directly, so the base name and the marker stay in sync across a rename or a flip. The
  suffix rides on `page_title`, which both feeds `Bond.window_bar` (via `window_title`)
  and drives the document `<title>`, so recomputing it updates both at once. The native
  macOS title is painted-hidden ([ADR 0013](0013-transparent-native-title-bar.html)) and
  so is left out of this entirely.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias LocalCentsWeb.Sync.PeerClient
  alias Phoenix.LiveView.Socket

  @offline_suffix " (Offline)"

  @doc """
  Seeds the offline state and keeps `page_title` marked while the link is suspended.

  Assigns `:link_state` from `PeerClient.link_state/0`, subscribes to link changes on
  the connected mount, and attaches a `handle_info` hook that recomputes `page_title`
  from the current base whenever the link flips.
  """
  @spec on_mount(:default, params :: map(), session :: map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: PeerClient.subscribe()

    socket =
      socket
      |> assign(:link_state, PeerClient.link_state())
      |> assign(:page_title_base, nil)
      |> attach_hook(:window_title, :handle_info, &recompute_on_flip/2)

    {:cont, socket}
  end

  @doc """
  Sets the window title to `base`, adding the `(Offline)` marker when the link is
  suspended.

  Views call this instead of assigning `page_title` directly, so the base name is
  remembered and the marker survives a later flip.
  """
  @spec put_title(Socket.t(), base :: String.t()) :: Socket.t()
  def put_title(socket, base) do
    socket
    |> assign(:page_title_base, base)
    |> assign(:page_title, decorate(base, socket.assigns.link_state))
  end

  # Recompute the title from the remembered base on each user flip. Every other message
  # falls through to the view's own `handle_info` clauses.
  defp recompute_on_flip({:sync_link, state}, socket) do
    socket =
      socket
      |> assign(:link_state, state)
      |> assign(:page_title, decorate(socket.assigns.page_title_base, state))

    {:halt, socket}
  end

  defp recompute_on_flip(_message, socket), do: {:cont, socket}

  defp decorate(nil, _state), do: nil
  defp decorate(base, :offline), do: base <> @offline_suffix
  defp decorate(base, _state), do: base
end
