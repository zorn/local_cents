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

    test "a Book that never had a viewer stays resident (Philosophy B)", %{tmp_dir: dir} do
      # create_book starts a server with no window; a bare open_book likewise. Neither
      # ever holds a viewer, so neither is ever reaped — only explicit close/1 stops it.
      {:ok, book} = Tracking.create_book("Family", books_dir: dir)

      server = server_pid(book.id)
      ref = Process.monitor(server)

      refute_receive {:DOWN, ^ref, :process, ^server, _}, 100
      assert BookServer.alive?(book.id)
    end

    test "reopening right after closing yields a live, serving process", %{tmp_dir: dir} do
      # Open-after-close race: `close_book/1` stops the server, but the Registry clears
      # its entry asynchronously, so an immediate reopen can be answered with the
      # not-yet-cleared (dead) pid whose next call would exit :noproc. `ensure_started/2`
      # confirms liveness and retries while the registry drains, so the caller always
      # gets a live, serving process.
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

  # A viewer is any process that registers itself via `Tracking.register_viewer/1`;
  # no LiveView is needed to exercise the runtime. It stays alive until `stop_viewer/1`
  # kills it, at which point Presence drops it and the server reconciles.
  defp start_viewer(book_id) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _ref} = Tracking.register_viewer(book_id)
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

  # Blocks until the server has processed a presence join (so `ever_had_viewer?` is
  # set), avoiding a race where a viewer registers and leaves before the server has
  # observed it — which would otherwise coalesce into a net-empty diff and never arm.
  defp await_viewer_observed(server) do
    wait_until(fn -> :sys.get_state(server).ever_had_viewer? end)
  end

  defp wait_until(fun, remaining \\ 1_000)

  defp wait_until(_fun, remaining) when remaining <= 0, do: flunk("condition not met in time")

  defp wait_until(fun, remaining) do
    case fun.() do
      false -> then_retry(fun, remaining)
      nil -> then_retry(fun, remaining)
      truthy -> truthy
    end
  end

  defp then_retry(fun, remaining) do
    Process.sleep(10)
    wait_until(fun, remaining - 10)
  end
end
