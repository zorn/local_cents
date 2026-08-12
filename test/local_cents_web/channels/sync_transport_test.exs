defmodule LocalCentsWeb.Sync.TransportTest do
  # End-to-end proof of the two-peer sync transport over a *real* WebSocket: a real
  # `LocalCentsWeb.Sync.PeerClient` dials the endpoint's `LocalCentsWeb.Sync.Channel`
  # over loopback, and an edit on either connected peer reaches the other (ADR 0025,
  # acceptance criterion 5). The channel-only and client-only tests emulate the wire;
  # this one runs the actual socket, so it catches the wiring they cannot — the
  # envelope, the topic, and the JSON serialization.
  #
  # async: false — the test flips the shared endpoint into `server: true` and restarts
  # it to open a real listener, a global change no concurrent test can tolerate. ExUnit
  # runs synchronous modules alone, after the async ones finish, so nothing else is
  # live while the endpoint is reconfigured.
  use ExUnit.Case, async: false

  import LocalCents.SyncTestHelper

  alias LocalCents.Eventually
  alias LocalCents.Tracking
  alias LocalCentsWeb.Sync.PeerClient

  @moduletag :tmp_dir

  # A dedicated port, distinct from the dev server's 4000 (which `runtime.exs` sets and
  # would otherwise win over `test.exs`), so a running dev instance never collides here.
  @port 4010

  setup_all do
    original = Application.get_env(:local_cents, LocalCentsWeb.Endpoint)

    serving =
      original
      |> Keyword.put(:server, true)
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: @port)

    Application.put_env(:local_cents, LocalCentsWeb.Endpoint, serving)
    restart_endpoint()

    on_exit(fn ->
      Application.put_env(:local_cents, LocalCentsWeb.Endpoint, original)
      restart_endpoint()
    end)

    :ok
  end

  test "an edit on either connected peer reaches the other", %{tmp_dir: dir} do
    # The origin peer holds the Book the dialer joins by topic; the dialer forks it, so
    # the two share an Automerge ancestor but keep their own ids and `.lcbook` files —
    # the shape of a peer seeded over the sync link (ADR 0025).
    {:ok, origin} = Tracking.create_book("Family", books_dir: dir)
    {:ok, coffee} = Tracking.add_expense(origin.id, %{description: "Coffee", cost: "1.00"})
    dialer_id = fork_peer(dir, origin.id)

    start_supervised!(
      {PeerClient,
       uri: "ws://127.0.0.1:#{@port}/peer/websocket",
       book_id: dialer_id,
       remote_book_id: origin.id}
    )

    # origin -> dialer: an edit on the dialed peer reaches the client's Book.
    {:ok, _} = Tracking.edit_expense(origin.id, coffee.id, %{description: "Espresso"})
    Eventually.wait_until(fn -> description(dialer_id, coffee.id) == "Espresso" end)

    # dialer -> origin: an edit on the client's Book reaches the dialed peer.
    {:ok, lunch} = Tracking.add_expense(dialer_id, %{description: "Lunch", cost: "2.00"})
    Eventually.wait_until(fn -> description(origin.id, lunch.id) == "Lunch" end)
  end

  defp restart_endpoint do
    Supervisor.terminate_child(LocalCents.Supervisor, LocalCentsWeb.Endpoint)

    # `restart_child/2` returns `{:ok, pid}` or `{:ok, pid, info}` depending on the child;
    # accept either success shape and let any other return fail the match loudly.
    case Supervisor.restart_child(LocalCents.Supervisor, LocalCentsWeb.Endpoint) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
    end
  end

  defp description(book_id, expense_id) do
    case expense(book_id, expense_id) do
      nil -> nil
      expense -> expense.description
    end
  end
end
