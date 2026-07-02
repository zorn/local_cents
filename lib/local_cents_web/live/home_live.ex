defmodule LocalCentsWeb.HomeLive do
  use LocalCentsWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
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
    {:noreply, assign(socket, count: count)}
  end
end
