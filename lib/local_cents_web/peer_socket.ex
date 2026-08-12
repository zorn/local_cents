defmodule LocalCentsWeb.PeerSocket do
  @moduledoc """
  The WebSocket a sync peer connects on, kept separate from the LiveView socket so
  peer-to-peer traffic never mixes with browser clients.

  It carries one channel, `LocalCentsWeb.Sync.Channel`, on the `"sync:<book_id>"`
  topic. The dialing peer is `LocalCentsWeb.Sync.PeerClient`, another BEAM on the
  local machine (ADR 0025); the demo wires the two by hand over loopback, so this
  socket authorizes every connection. A networked deployment would add peer
  authentication here before that assumption leaves the demo.
  """

  use Phoenix.Socket

  channel "sync:*", LocalCentsWeb.Sync.Channel

  @impl Phoenix.Socket
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  # No per-peer identity yet: each connection is its own transient sync session, so
  # there is nothing to resume by id.
  @impl Phoenix.Socket
  def id(_socket), do: nil
end
