defmodule LocalCentsWeb.HomeLive do
  @moduledoc """
  The interim landing view mounted at `/`.

  This is a placeholder counter left over from wiring up the Tauri bridge — the
  increment button broadcasts a `count:*` message over `ElixirKit.PubSub`, which
  exercises the Elixir → native channel end to end. It stands in until the real
  library/home screens from the MVP replace it.
  """
  use LocalCentsWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(count: 0)
    |> ok()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between m-4">
      <div class="flex items-center gap-2">
        <span>Count: <span class="font-mono">{@count}</span></span>
        <button
          phx-click="inc"
          class="px-2 py-1 text-sm font-medium border border-gray-300 rounded hover:bg-gray-100 dark:border-gray-600 dark:hover:bg-gray-800 transition-colors"
        >
          +
        </button>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("inc", _params, socket) do
    count = socket.assigns.count + 1
    ElixirKit.PubSub.broadcast("messages", "count:#{count}")

    socket
    |> assign(count: count)
    |> noreply()
  end
end
