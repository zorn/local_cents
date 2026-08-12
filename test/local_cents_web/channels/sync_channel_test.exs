defmodule LocalCentsWeb.Sync.ChannelTest do
  # The host side of the two-peer sync transport (ADR 0025): a peer dials into this
  # channel and the two exchange Automerge sync messages over it. These tests drive
  # the channel through its real message interface — join, an inbound "sync" frame, a
  # local edit — and assert what it pushes back. Convergence of two real peers over a
  # live WebSocket is proven by the integration test that connects with a
  # `LocalCentsWeb.Sync.PeerClient`; here the test stands in for the remote peer.
  #
  # Async: each test seeds its Book into its own `:tmp_dir`, and the sync calls reach
  # the already-running `BookServer` by id, so no shared `:books_dir` forces
  # serialization.
  use LocalCentsWeb.ChannelCase, async: true

  import LocalCents.SyncTestHelper
  import TinyMaps

  alias LocalCents.Tracking
  alias LocalCentsWeb.PeerSocket
  alias LocalCentsWeb.Sync.Channel
  alias LocalCentsWeb.Sync.Message

  @moduletag :tmp_dir

  test "joining the channel initiates the sync exchange", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})

    {:ok, _reply, _socket} = join(book.id)

    # A fresh sync state has no knowledge of the remote, so the channel opens the
    # exchange by pushing its first sync message rather than waiting to be asked.
    assert_push "sync", %{message: _message}
  end

  test "a local edit after join pushes the change to the peer", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})

    {:ok, _reply, _socket} = join(book.id)
    assert_push "sync", %{message: _opening}

    # An edit on this side broadcasts `:book_updated`; the channel is subscribed, so
    # it wakes and pushes the peer the change it is now missing.
    {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})

    assert_push "sync", %{message: _message}
  end

  test "an inbound sync message is answered with the change the peer lacks", ~M{tmp_dir} do
    {:ok, book} = Tracking.create_book("Family", books_dir: tmp_dir)
    {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "1.00"})

    # A peer forks from the shared ancestor, then this side edits ahead of it.
    peer_id = fork_peer(tmp_dir, book.id)
    peer = make_ref()
    {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})

    {:ok, _reply, socket} = join(book.id)
    assert_push "sync", %{message: _opening}

    # The peer's opening message tells the channel what the peer already has; the
    # channel answers with a message carrying the "Espresso" edit the peer lacks.
    opening = Tracking.generate_sync_message(peer_id, peer)
    push(socket, "sync", %{"message" => Base.encode64(opening)})

    assert_push "sync", %{message: reply}

    # Applying the channel's reply back onto the peer converges it on the edit.
    {:ok, reply_bytes} = Message.unwrap(%{"message" => reply})
    :ok = Tracking.receive_sync_message(peer_id, peer, reply_bytes)
    assert %{description: "Espresso"} = expense(peer_id, coffee.id)
  end

  test "joining a Book with no running server does not push or crash" do
    # A peer can dial in before this side has opened the Book. With no server to sync,
    # the channel joins and idles rather than crashing on the opening exchange.
    book_id = Ecto.UUID.generate()

    {:ok, _reply, socket} = join(book_id)

    refute_push "sync", _payload

    # A malformed envelope is dropped rather than crashing the channel.
    push(socket, "sync", %{"message" => "not valid base64 !!"})

    # A synchronous state read drains the async push above and returns (rather than
    # exiting) only if it did not crash the channel.
    assert :sys.get_state(socket.channel_pid)
  end

  defp join(book_id) do
    PeerSocket
    |> socket(nil, %{})
    |> subscribe_and_join(Channel, "sync:" <> book_id)
  end
end
