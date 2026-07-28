defmodule LocalCents.Tracking.BookServerShutdownTest do
  # Async: each test seeds its Book into its own `:tmp_dir` and every Book has a
  # unique id, so the per-Book presence topics and BookServers never collide. The
  # grace period is a shared (unmutated) config value, so it forces no serialization.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking
  alias LocalCents.Tracking.BookServer

  @moduletag :tmp_dir

  describe "auto-shutdown on last viewer" do
    test "reaps after the last viewer disconnects, and the document survives", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

      server = server_pid(book.id)
      ref = Process.monitor(server)

      viewer = start_viewer(book.id)
      await_viewer_observed(server)

      stop_viewer(viewer)

      # Grace period elapses with no viewer → the server stops :normal (its
      # terminate/2 performs the redundant final persist).
      assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000

      # Reopening reloads the persisted document intact.
      :ok = Tracking.open_book(book.id, books_dir: dir)
      assert [%Tracking.Expense{description: "Coffee"}] = Tracking.list_expenses(book.id)
    end

    test "stays resident while at least one viewer remains", %{tmp_dir: dir} do
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      server = server_pid(book.id)
      ref = Process.monitor(server)

      keeper = start_viewer(book.id)
      leaver = start_viewer(book.id)
      await_viewer_observed(server)

      stop_viewer(leaver)

      # One viewer down, one remaining: no reap.
      refute_receive {:DOWN, ^ref, :process, ^server, _}, 100
      assert BookServer.alive?(book.id)

      stop_viewer(keeper)
      assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000
    end

    test "a viewer returning within the grace window cancels the reap (nav gap)", %{tmp_dir: dir} do
      # The push_navigate between a Book's views (ADR 0017) is a full remount: the old
      # viewer leaves, then a new one joins moments later. The grace period must bridge
      # that gap so ordinary navigation does not tear the process down.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      server = server_pid(book.id)
      ref = Process.monitor(server)

      leaving = start_viewer(book.id)
      await_viewer_observed(server)

      stop_viewer(leaving)
      # Re-register immediately, well within the (test-shrunk) grace period.
      arriving = start_viewer(book.id)

      refute_receive {:DOWN, ^ref, :process, ^server, _}, 100
      assert BookServer.alive?(book.id)

      stop_viewer(arriving)
      assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000
    end

    test "a Book that never had a viewer stays resident", %{tmp_dir: dir} do
      # create_book starts a server with no window; a bare open_book likewise. Neither
      # ever holds a viewer, so neither is ever reaped — only explicit close/1 stops it.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      server = server_pid(book.id)
      ref = Process.monitor(server)

      refute_receive {:DOWN, ^ref, :process, ^server, _}, 100
      assert BookServer.alive?(book.id)
    end

    test "reopening right after closing yields a live, serving process", %{tmp_dir: dir} do
      # Open-after-close: `close_book/1` stops the server, and auto-shutdown makes this
      # churn routine. The reopen is safe with no guard in `ensure_started/2` because
      # `Registry` registration for `:unique` keys evicts a dead holder and retries
      # before it will report `{:already_started, _}` — so the pid handed back is always
      # live. This pins that, since a regression there would surface as a `:noproc` exit
      # on the next call rather than anything louder.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)
      {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "5.00"})

      before = server_pid(book.id)
      :ok = Tracking.close_book(book.id)

      # Reopen immediately — the Registry may not have cleared `before` yet.
      :ok = Tracking.open_book(book.id, books_dir: dir)

      live = server_pid(book.id)
      assert live != before
      assert Process.alive?(live)
      # Would exit :noproc here if we had been handed the dead pid.
      assert [%Tracking.Expense{description: "Coffee"}] = Tracking.list_expenses(book.id)
    end

    test "a viewer tracked across a restart keeps the new server resident", %{tmp_dir: dir} do
      # Presence lives in its own process, so a viewer stays tracked even while the
      # Book's server is down. On restart the new server must see it via Presence.list
      # at init and stay resident rather than reaping. Closing and reopening exercises
      # exactly the init path a crash-restart would — the same `Presence.list`-at-init
      # read — without brutally killing a supervised process (a `Process.exit/2` :kill
      # would propagate through the BookServer's link to the shared Registry/PubSub
      # partitions and, being bidirectional, could disturb unrelated Books).
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      viewer = start_viewer(book.id)
      await_viewer_observed(server_pid(book.id))

      :ok = Tracking.close_book(book.id)
      :ok = Tracking.open_book(book.id, books_dir: dir)

      restarted = server_pid(book.id)
      ref = Process.monitor(restarted)

      # The viewer, still tracked across the restart, keeps the new server resident.
      refute_receive {:DOWN, ^ref, :process, ^restarted, _}, 100
      assert BookServer.alive?(book.id)

      # And once the viewer finally leaves, it reaps.
      stop_viewer(viewer)
      assert_receive {:DOWN, ^ref, :process, ^restarted, :normal}, 1_000
    end
  end

  describe "what actually gates the reap" do
    test "a Book that never had a viewer receives no presence_diff at all", %{tmp_dir: dir} do
      # The load-bearing fact behind that rule. A `presence_diff` is only broadcast on
      # a topic something has tracked on, and the only thing that ever tracks on
      # `presence_topic/1` is `register_viewer/1`. So a never-viewed Book's server is
      # never woken to reconcile, which is what keeps it resident — no server-side flag
      # is required to achieve it.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      Phoenix.PubSub.subscribe(LocalCents.PubSub, BookServer.presence_topic(book.id))

      refute_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 100
      assert BookServer.alive?(book.id)
    end

    test "a viewer gone before the server observes its join still arms the reap", %{tmp_dir: dir} do
      # The server reconciles by re-reading `Presence.list/1`, not by inspecting the
      # diff payload, so a viewer that dies before the server drains its mailbox is
      # never *seen* as present — both the join and the leave diff are processed against
      # an already-empty presence set. The Book must still reap: a viewer did exist, and
      # the arrival of a diff on this topic is itself the proof.
      #
      # Suspending the server makes that ordering deterministic rather than a race:
      # both diffs queue while it is frozen and are handled only after the viewer is
      # gone. This one tracks through `BookServer.register_viewer/1` rather than the
      # `Tracking` facade, because the facade also reads the Book back from the server
      # and would block on the suspension; the presence side — all this test cares
      # about — is identical either way.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      server = server_pid(book.id)
      ref = Process.monitor(server)

      :sys.suspend(server)
      viewer = start_tracked_only_viewer(book.id)
      stop_viewer(viewer)
      :sys.resume(server)

      assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000
    end
  end

  # A viewer is any process that registers itself via `Tracking.register_viewer/1`;
  # no LiveView is needed to exercise the runtime. It stays alive until `stop_viewer/1`
  # kills it, at which point Presence drops it and the server reconciles.
  defp start_viewer(book_id) do
    spawn_viewer(fn -> {:ok, %Tracking.Book{}} = Tracking.register_viewer(book_id) end)
  end

  # Tracks presence without the facade's follow-up read of the Book, for the one test
  # that runs against a suspended server.
  defp start_tracked_only_viewer(book_id) do
    spawn_viewer(fn -> {:ok, _ref} = BookServer.register_viewer(book_id) end)
  end

  defp spawn_viewer(register) do
    test = self()

    pid =
      spawn(fn ->
        register.()
        send(test, :registered)
        Process.sleep(:infinity)
      end)

    assert_receive :registered, 1_000
    pid
  end

  defp stop_viewer(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
  end

  defp server_pid(book_id) do
    [{pid, _}] = Registry.lookup(LocalCents.Tracking.BookRegistry, book_id)
    pid
  end

  # Blocks until the server has processed the viewer's join diff. The tracker reports a
  # join *before* it records the presence, so by the time `register_viewer/1` returns
  # the diff is already in this server's mailbox; a `:sys.get_state/1` round-trip is
  # therefore a sufficient barrier — it is replied to only after the queued diff has
  # been handled. No polling needed.
  defp await_viewer_observed(server) do
    _ = :sys.get_state(server)
    :ok
  end
end
