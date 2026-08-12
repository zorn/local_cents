defmodule LocalCentsWeb.Sync.Channel do
  @moduledoc """
  The host side of the two-peer sync transport: a peer dials into this Channel and
  the two exchange Automerge sync messages over it until they converge (ADR 0025).

  One joined Channel process reconciles one open Book with one connected peer. It
  drives the same exchange the in-process tracking sync tests prove, but over a real
  WebSocket:

    * on join it opens the exchange by pushing its first sync message — a fresh sync
      state knows nothing about the remote, so there is always an opening message;
    * an inbound `"sync"` frame is folded into the Book and answered with the next
      message the exchange owes;
    * a local edit — surfaced as a `:book_updated` broadcast on the Book's PubSub
      topic — pushes the change the peer is now missing.

  The Channel holds no document; it delegates every sync step to the
  `LocalCents.Tracking` context, so the peer's per-peer sync state lives in the
  Book's `BookServer`, keyed by the `peer` handle this Channel picks at join. The
  dialing half is `LocalCentsWeb.Sync.PeerClient`.
  """

  use Phoenix.Channel

  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.Message

  @impl Phoenix.Channel
  def join("sync:" <> book_id, _payload, socket) do
    # A per-connection handle keys this peer's sync state in the Book's `BookServer`;
    # a fresh ref keeps two connections to one Book from sharing a sync state.
    socket = assign(socket, book_id: book_id, peer: make_ref())
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_info(:after_join, socket) do
    # Subscribe before the opening message so no local edit that lands mid-exchange
    # is missed.
    :ok = Tracking.subscribe(socket.assigns.book_id)
    {:noreply, pump(socket)}
  end

  # A local edit (or a folded-in change from the peer) advanced the Book; send the
  # peer whatever it is now missing. The reconcile also emits `:categories_updated`,
  # but `:book_updated` always rides alongside it, so this one signal drives the pump.
  def handle_info({:book_updated, _book_id}, socket), do: {:noreply, pump(socket)}

  # Ignore the other broadcasts (e.g. `:categories_updated`) rather than crash on
  # them (ADR 0019).
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.Channel
  def handle_in("sync", payload, socket) do
    %{book_id: book_id, peer: peer} = socket.assigns

    with {:ok, message} <- Message.unwrap(payload),
         :ok <- Tracking.receive_sync_message(book_id, peer, message) do
      {:noreply, pump(socket)}
    else
      # A malformed envelope, or no open Book to fold into (a peer can dial in before
      # this side opens the Book): drop it rather than crash. The next exchange recovers.
      _ -> {:noreply, socket}
    end
  end

  # Generate the next sync message the Book owes the peer and push it, or do nothing
  # when the exchange has nothing to send — `nil` when converged, `{:error, :not_open}`
  # when this side has no open Book yet.
  defp pump(socket) do
    %{book_id: book_id, peer: peer} = socket.assigns

    case Tracking.generate_sync_message(book_id, peer) do
      message when is_binary(message) ->
        push(socket, "sync", Message.wrap(message))

      # `nil` (nothing to send) or `{:error, :not_open}` (no open Book yet): idle.
      _ ->
        :ok
    end

    socket
  end
end
