defmodule LocalCentsWeb.Sync.MenuBridge do
  @moduledoc """
  Ties the native Developer menu's offline-mode item to the sync link.

  The offline toggle is a native macOS menu item (`tauri/src/lib.rs`), not a web control,
  so its two directions cross the `ElixirKit.PubSub` bridge (ADR 0025):

    * a click arrives from Rust as `{"action":"toggle-offline"}` on the `"messages"`
      channel; this process folds it into `LocalCentsWeb.Sync.PeerClient.toggle_link/0`;
    * a link-state change — `PeerClient`'s `{:sync_link, state}` broadcast — goes back to
      Rust through `LocalCentsWeb.DesktopShell.set_offline_menu/1`, which relabels the item.

  It holds no state of its own; `PeerClient` owns the link and the menu only mirrors it.
  Started only under the native shell (see `LocalCents.Application`), because without the
  bridge there is no menu to drive and nothing broadcasts the click.
  """

  use GenServer

  alias LocalCentsWeb.DesktopShell
  alias LocalCentsWeb.Sync.PeerClient

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    # Hear the menu's clicks from Rust, and the link's state changes from PeerClient.
    :ok = ElixirKit.PubSub.subscribe("messages")
    :ok = PeerClient.subscribe()

    # Report the link's current state so the item opens enabled and labeled rather than
    # waiting for the first flip. `nil` (no peer configured) sends nothing, leaving the
    # item disabled — there is no link to toggle.
    push_menu(PeerClient.link_state())

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:sync_link, state}, menu_bridge) do
    push_menu(state)
    {:noreply, menu_bridge}
  end

  # An inbound bridge message is the Rust side's raw JSON payload.
  def handle_info(message, menu_bridge) when is_binary(message) do
    if action(message) == "toggle-offline", do: PeerClient.toggle_link()
    {:noreply, menu_bridge}
  end

  # Ignore anything else on the bridge rather than crash (ADR 0019).
  def handle_info(_message, menu_bridge), do: {:noreply, menu_bridge}

  defp push_menu(nil), do: :ok
  defp push_menu(state), do: DesktopShell.set_offline_menu(state)

  defp action(message) do
    case Jason.decode(message) do
      {:ok, %{"action" => action}} -> action
      _ -> nil
    end
  end
end
