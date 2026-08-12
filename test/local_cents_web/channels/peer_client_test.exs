defmodule LocalCentsWeb.Sync.PeerClientTest do
  # The dialing side of the two-peer sync transport (ADR 0025): this client connects
  # to the other peer's `LocalCentsWeb.Sync.Channel` and the two exchange Automerge
  # sync messages. These tests use `Slipstream.SocketTest`, which lets the test
  # process play the remote server — asserting what the client pushes and simulating
  # what the server pushes back. End-to-end convergence over a live WebSocket is the
  # integration test's job; here the wire is emulated.
  #
  # async: false — `Slipstream.SocketTest` models exactly one server per test and the
  # client is started as a named singleton, so two of these tests must not run at once.
  use Slipstream.SocketTest, async: false

  import LocalCents.SyncTestHelper

  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.PeerClient

  @moduletag :tmp_dir

  test "joining opens the exchange with a first sync message", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: dir)
    {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})
    topic = "sync:" <> book.id

    start_client(book.id)

    connect_and_assert_join(PeerClient, ^topic, %{}, :ok)
    assert_push ^topic, "sync", %{message: _message}
  end

  test "an inbound sync message is answered with the change the peer lacks", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: dir)
    {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})
    topic = "sync:" <> book.id

    # A peer forks from the shared ancestor; this side then edits ahead of it.
    peer_id = fork_peer(dir, book.id)
    peer = make_ref()
    {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})

    start_client(book.id)
    connect_and_assert_join(PeerClient, ^topic, %{}, :ok)
    assert_push ^topic, "sync", %{message: _opening}

    # Play the peer: its opening message tells the client what it already has, and the
    # client answers with a message carrying the "Espresso" edit the peer lacks.
    peer_opening = Tracking.generate_sync_message(peer_id, peer)
    push(PeerClient, topic, "sync", %{"message" => Base.encode64(peer_opening)})

    assert_push ^topic, "sync", %{message: reply}
    :ok = Tracking.receive_sync_message(peer_id, peer, Base.decode64!(reply))
    assert %{description: "Espresso"} = expense(peer_id, coffee.id)
  end

  test "a local edit after join pushes the change to the peer", %{tmp_dir: dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: dir)
    {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})
    topic = "sync:" <> book.id

    start_client(book.id)
    connect_and_assert_join(PeerClient, ^topic, %{}, :ok)
    assert_push ^topic, "sync", %{message: _opening}

    # An edit on this side broadcasts `:book_updated`; the client is subscribed, so it
    # wakes and pushes the peer the change it is now missing.
    {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})

    assert_push ^topic, "sync", %{message: _message}
  end

  test "stays alive when its local Book has no running server", %{tmp_dir: _dir} do
    # The client can be started before its Book is opened (it auto-starts from the
    # supervision tree). With no server for the Book, the exchange has nothing to do
    # rather than crashing the client.
    book_id = Ecto.UUID.generate()
    topic = "sync:" <> book_id

    client = start_client(book_id)
    connect_and_assert_join(PeerClient, ^topic, %{}, :ok)

    # Nothing to send: there is no open Book to generate a message from.
    refute_push ^topic, "sync", _payload

    # An inbound message with no Book to fold into, and a malformed envelope, are both
    # dropped rather than fatal.
    push(PeerClient, topic, "sync", %{"message" => Base.encode64("ignored")})
    push(PeerClient, topic, "sync", %{"message" => "not valid base64 !!"})

    # A synchronous state read drains the async pushes above and returns (rather than
    # exiting) only if neither crashed the client.
    assert :sys.get_state(client)
  end

  defp start_client(book_id) do
    start_supervised!(
      {PeerClient, uri: "ws://localhost:4001/peer/websocket", book_id: book_id, test_mode?: true}
    )
  end
end
