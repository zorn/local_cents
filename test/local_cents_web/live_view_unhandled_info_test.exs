defmodule LocalCentsWeb.LiveViewUnhandledInfoTest do
  # Guards the catch-all `handle_info/2` that `LocalCentsWeb.live_view/0` injects
  # into every LiveView: an unmatched message must be ignored (not crash), and a
  # view's own clauses must still win over the fallback.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Phoenix.LiveView.Socket

  defmodule ExampleLive do
    use LocalCentsWeb, :live_view

    @impl Phoenix.LiveView
    def handle_info(:known, socket) do
      send(self(), :handled_by_specific_clause)
      {:noreply, socket}
    end

    @impl Phoenix.LiveView
    def render(assigns), do: ~H""
  end

  test "a view's own clause still matches ahead of the injected fallback" do
    assert {:noreply, %Socket{}} = ExampleLive.handle_info(:known, %Socket{})
    assert_received :handled_by_specific_clause
  end

  test "an unmatched message is ignored instead of raising" do
    assert {:noreply, %Socket{}} = ExampleLive.handle_info(:surprise, %Socket{})
    refute_received :handled_by_specific_clause
  end

  test "the ignored message is logged at debug for visibility in development" do
    # No `Logger.configure/1` here, deliberately. The test env's primary level is
    # already `:debug` so `capture_log` can see this message, while the console
    # handler stays at `:warning` to keep the suite's output quiet (config/test.exs).
    # Lifting the level at runtime instead is a node-wide mutation, and it was the one
    # thing keeping this module `async: false`.
    log =
      capture_log(fn ->
        ExampleLive.handle_info({:some_future_signal, "abc"}, %Socket{})
      end)

    assert log =~ "ignored an unhandled message"
    assert log =~ ":some_future_signal"
  end
end
