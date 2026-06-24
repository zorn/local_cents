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
      <div class="max-w-2xl mx-auto py-10 space-y-12">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">UI Plugin Test</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Verifies dark mode, Tailwind Typography, and Tailwind Forms are working.
          </p>
        </div>

        <%!-- Dark mode --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            Dark Mode
          </h2>
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
          <div class="flex gap-3 flex-wrap pt-1">
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

        <%!-- Typography plugin --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            Typography Plugin
          </h2>
          <article class="prose dark:prose-invert max-w-none rounded-lg border border-gray-200 dark:border-gray-700 p-6">
            <h1>Heading one</h1>
            <h2>Heading two</h2>
            <p>
              This paragraph is styled by the <code>@tailwindcss/typography</code>
              plugin via the <strong>prose</strong>
              class. It handles font sizing, line height, spacing between
              headings and paragraphs, and code blocks automatically.
            </p>
            <ul>
              <li>Unordered list item one</li>
              <li>Unordered list item two</li>
            </ul>
            <blockquote>A blockquote styled by the typography plugin.</blockquote>
          </article>
        </section>

        <%!-- Forms plugin --%>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            Forms Plugin
          </h2>
          <div class="rounded-lg border border-gray-200 dark:border-gray-700 p-6 space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Text input
              </label>
              <input
                type="text"
                placeholder="e.g. Coffee at Blue Bottle"
                class="w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Select
              </label>
              <select class="w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
                <option>Food &amp; Drink</option>
                <option>Transport</option>
                <option>Shopping</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Textarea
              </label>
              <textarea
                rows="3"
                placeholder="Notes about this transaction..."
                class="w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
              ></textarea>
            </div>
            <div class="flex items-center gap-2">
              <input
                type="checkbox"
                id="recurring"
                class="rounded border-gray-300 dark:border-gray-600"
              />
              <label for="recurring" class="text-sm text-gray-700 dark:text-gray-300">
                Recurring transaction
              </label>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
