defmodule LocalCentsWeb.Sync.PeerClient do
  @moduledoc """
  The dialing side of the two-peer sync transport: a Slipstream client that connects
  to another peer's `LocalCentsWeb.Sync.Channel` and exchanges Automerge sync
  messages with it until the two Books converge (ADR 0025).

  It is the mirror of the Channel. Where the Channel is the peer that gets dialed,
  this is the peer that dials — the Mac app connecting out to the browser's server —
  which is why the offline toggle lives here: suspending the link is disconnecting
  this client, resuming is letting it reconnect.

  The exchange it drives is the same on both sides:

    * on joining the topic it opens the exchange with its first sync message;
    * an inbound `"sync"` message is folded into the Book and answered with the next
      message the exchange owes;
    * a local edit — a `:book_updated` broadcast on the Book's PubSub topic, which it
      subscribes to at start-up — pushes the peer the change it is now missing.

  Like the Channel it holds no document: every sync step delegates to the
  `LocalCents.Tracking` context, so the peer's sync state lives in the Book's
  `BookServer`. It reconciles a single Book, named by the `:book_id` it is started
  with; the `:uri` names the peer to dial.
  """

  use Slipstream

  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.Message

  require Logger

  # One remote peer per client, so its sync state needs only a single constant key.
  @peer :remote

  @doc """
  Starts the client, connecting to the peer at `:uri` to sync the local Book `:book_id`.

  The peer is joined on the topic for `:remote_book_id` — the id of the Book on the
  dialed side, which the two peers agree on as their rendezvous. It defaults to
  `:book_id` for the case where both peers carry the same id; a peer seeded over the
  sync link keeps its own local id and passes the origin's id here (ADR 0025).

  `:test_mode?` is passed through to Slipstream so `Slipstream.SocketTest` can drive
  the client without a live server.
  """
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    Slipstream.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The sync link's current state from the demo's point of view:

    * `:online` — the link is live;
    * `:offline` — the link has been suspended by `suspend/0`;
    * `nil` — no client is running, so there is no link (no peer configured).

  This reports the operator's intent, not the socket's moment-to-moment connection
  status, so a transient reconnect never reads as a deliberate offline.
  """
  @spec link_state() :: :online | :offline | nil
  def link_state do
    case GenServer.whereis(__MODULE__) do
      nil -> nil
      pid -> GenServer.call(pid, :link_state)
    end
  end

  @doc """
  Suspends the sync link — the Mac side going offline.

  Disconnects this client from the peer so no change crosses in either direction, and
  marks the link suspended so the drop is not auto-reconnected. The two documents keep
  accepting edits independently until `resume/0`. A no-op when no client is running.
  """
  @spec suspend() :: :ok
  def suspend, do: cast(:suspend)

  @doc """
  Resumes the sync link — the Mac side coming back online.

  Redials the peer and rejoins, which reopens the exchange so each side catches the
  other up on the edits it missed while the link was down. A no-op when no client is
  running.
  """
  @spec resume() :: :ok
  def resume, do: cast(:resume)

  @doc """
  Flips the link — `suspend/0` when it is online, `resume/0` when it is offline.

  The client owns which way to flip because it owns the state, so the Mac-side toggle
  can ask for the flip without first reading `link_state/0`. A no-op when no client is
  running.
  """
  @spec toggle_link() :: :ok
  def toggle_link, do: cast(:toggle)

  @doc """
  Subscribes the calling process to link-state changes.

  Each flip broadcasts `{:sync_link, :online | :offline}`. `LocalCentsWeb.Sync.MenuBridge`
  subscribes so the native offline-mode menu item mirrors the link's state.
  """
  @spec subscribe() :: :ok
  def subscribe, do: Phoenix.PubSub.subscribe(LocalCents.PubSub, link_topic())

  @doc """
  The `Phoenix.PubSub` topic that link-state changes broadcast on.

  The link is a single global stream, so it is a bare `<kind>` (see
  [ADR 0011](0011-pubsub-topic-naming.html)). Named here so callers never hand-build it.
  """
  @spec link_topic() :: String.t()
  def link_topic, do: "sync-link"

  # Casts `message` to the running client, or does nothing when no peer is configured so
  # the toggle can call blindly without first checking whether a link exists.
  defp cast(message) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, message)
    end
  end

  defp broadcast_link_state(state) do
    Phoenix.PubSub.broadcast(LocalCents.PubSub, link_topic(), {:sync_link, state})
  end

  @impl Slipstream
  def init(opts) do
    book_id = Keyword.fetch!(opts, :book_id)
    topic = Message.topic(Keyword.get(opts, :remote_book_id, book_id))

    # Subscribe before connecting so no local edit that lands during the handshake is
    # missed — the exchange it triggers is held until the topic is joined (see `pump/1`).
    :ok = Tracking.subscribe(book_id)

    case connect(Keyword.take(opts, [:uri, :test_mode?])) do
      {:ok, socket} ->
        {:ok, assign(socket, book_id: book_id, peer: @peer, topic: topic, suspended?: false)}

      # A bad `:uri` is the only way `connect/1` fails synchronously — an unreachable
      # peer still connects (Slipstream retries in the background). Since this client is
      # supervised in the app tree, crashing here would restart-loop and could take the
      # whole app down on a misconfigured sync URL, so skip the child and log instead.
      {:error, reason} ->
        Logger.warning("Sync PeerClient did not start: #{inspect(reason)}")
        :ignore
    end
  end

  @impl Slipstream
  def handle_connect(socket) do
    {:ok, join(socket, socket.assigns.topic)}
  end

  @impl Slipstream
  def handle_join(_topic, _reply, socket), do: {:ok, pump(socket)}

  @impl Slipstream
  def handle_message(_topic, "sync", payload, socket) do
    %{book_id: book_id, peer: peer} = socket.assigns

    with {:ok, message} <- Message.unwrap(payload),
         :ok <- Tracking.receive_sync_message(book_id, peer, message) do
      {:ok, pump(socket)}
    else
      # A malformed envelope, or no open Book to fold into (the link can outlive an open
      # Book): drop it rather than crash the client. The next exchange recovers.
      _ -> {:ok, socket}
    end
  end

  @impl Slipstream
  def handle_call(:link_state, _from, socket) do
    {:reply, if(socket.assigns.suspended?, do: :offline, else: :online), socket}
  end

  @impl Slipstream
  def handle_cast(:suspend, socket) do
    _ = broadcast_link_state(:offline)
    {:noreply, socket |> assign(suspended?: true) |> disconnect()}
  end

  def handle_cast(:resume, socket) do
    _ = broadcast_link_state(:online)
    socket = assign(socket, suspended?: false)

    # `reconnect/1` refuses (`{:error, :connected}`) when the link never actually
    # dropped — a resume with nothing to resume — so keep the socket as-is there.
    case reconnect(socket) do
      {:ok, socket} -> {:noreply, socket}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # The flip lives here, next to the state it reads, rather than in the web-side toggle.
  def handle_cast(:toggle, %{assigns: %{suspended?: true}} = socket),
    do: handle_cast(:resume, socket)

  def handle_cast(:toggle, socket), do: handle_cast(:suspend, socket)

  # A disconnect the toggle asked for stays down until `resume/0`; any other is
  # unexpected, so reconnect with backoff as Slipstream's default does — an unreachable
  # peer must keep retrying rather than give up the link for good.
  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    if socket.assigns.suspended? do
      {:ok, socket}
    else
      # Keep the socket `reconnect/1` returns — it carries the advanced backoff
      # counter, so a peer that stays down retries on a lengthening interval toward
      # the 5s step rather than hot-looping at the first 10ms one. Tolerate an
      # `{:error, …}` so a reconnect it can't schedule never crash-loops the client.
      case reconnect(socket) do
        {:ok, socket} -> {:ok, socket}
        {:error, _reason} -> {:ok, socket}
      end
    end
  end

  @impl Slipstream
  def handle_info({:book_updated, _book_id}, socket), do: {:noreply, pump(socket)}

  # Ignore the other broadcasts (e.g. `:categories_updated`, which always rides
  # alongside `:book_updated`) rather than crash on them (ADR 0019).
  def handle_info(_message, socket), do: {:noreply, socket}

  # Generate the next sync message the Book owes the peer and push it, or do nothing
  # when the exchange has nothing to send. Guarded on `joined?/2`: a local edit can
  # arrive before the topic is joined, and generating then would advance the sync
  # state for a message the client cannot yet send. Skipping it is safe — the
  # post-join opening message carries that change.
  defp pump(socket) do
    topic = socket.assigns.topic

    if joined?(socket, topic) do
      case Tracking.generate_sync_message(socket.assigns.book_id, socket.assigns.peer) do
        message when is_binary(message) ->
          _ = push(socket, topic, "sync", Message.wrap(message))

        # `nil` (nothing to send) or `{:error, :not_open}` (no local Book yet): idle.
        _ ->
          :ok
      end
    end

    socket
  end
end
