defmodule LocalCentsWeb.ThemeTestLive do
  use LocalCentsWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto py-10 space-y-10">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Dark Mode Test</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Use the toggle in the header to switch between system, light, and dark modes.
          </p>
        </div>

        <%!-- Color swatches --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Text colors</h2>
          <p class="text-gray-900 dark:text-white">Primary text — gray-900 / white</p>
          <p class="text-gray-600 dark:text-gray-300">Secondary text — gray-600 / gray-300</p>
          <p class="text-gray-400 dark:text-gray-500">Muted text — gray-400 / gray-500</p>
        </section>

        <%!-- Surfaces --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Surfaces</h2>
          <div class="rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4">
            <p class="text-gray-900 dark:text-white font-medium">Card surface</p>
            <p class="text-sm text-gray-500 dark:text-gray-400">bg-white / bg-gray-800 with border</p>
          </div>
          <div class="rounded-lg bg-gray-50 dark:bg-gray-900 p-4">
            <p class="text-gray-900 dark:text-white font-medium">Subtle surface</p>
            <p class="text-sm text-gray-500 dark:text-gray-400">bg-gray-50 / bg-gray-900</p>
          </div>
        </section>

        <%!-- Buttons --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Buttons</h2>
          <div class="flex gap-3 flex-wrap">
            <button class="px-4 py-2 bg-orange-500 hover:bg-orange-600 text-white text-sm font-medium rounded-lg transition-colors">
              Primary
            </button>
            <button class="px-4 py-2 bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-900 dark:text-white text-sm font-medium rounded-lg transition-colors">
              Secondary
            </button>
            <button class="px-4 py-2 border border-gray-300 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300 text-sm font-medium rounded-lg transition-colors">
              Outline
            </button>
          </div>
        </section>

        <%!-- Status colors --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Status</h2>
          <div class="flex gap-3 flex-wrap">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
              Income
            </span>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
              Expense
            </span>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
              Transfer
            </span>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
