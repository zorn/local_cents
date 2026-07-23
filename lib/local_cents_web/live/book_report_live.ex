defmodule LocalCentsWeb.BookReportLive do
  @moduledoc """
  A single open `Book`'s **Report** — its Category × Month spending matrix — mounted
  at `/books/:book_id/report`.

  A secondary page of the Book's one native document window, reached by navigating
  from `LocalCentsWeb.BookLive` (see
  [ADR 0017](0017-in-window-secondary-views.html)). It repeats that view's mount
  contract — ensure the Book's runtime process is running, then subscribe to its
  change broadcasts.

  Two decisions shape how it loads and stays current:

    * **Range selector** (see [ADR 0021](0021-bounded-report-range.html)). A control
      picks the trailing **Report range** — the last 3/6/12/24 Months or All time,
      defaulting to 6. The choice lives in the URL (`?range=6`) so it is reload-stable
      and shareable, and changing it recomputes.
    * **Refresh on demand** (see [ADR 0022](0022-report-refreshes-on-demand.html)).
      The Report is an expensive read model loaded asynchronously off the mount path
      (a `Bond.loading_state` shows on first load). Unlike the sibling editing views,
      it does **not** recompute when the Book changes elsewhere: a `{:book_updated}`
      marks it stale and offers a Refresh button rather than shifting the numbers
      under a reader. A rename still updates the title live, and a deletion still
      redirects to the library.
  """
  use LocalCentsWeb, :live_view

  alias LocalCents.Tracking
  alias LocalCents.Tracking.Book
  alias LocalCentsWeb.DesktopShell
  alias LocalCentsWeb.ReportPresenter

  # The trailing-range presets, as {select label, URL key}. "6" is the default.
  @range_options [
    {"Last 3 months", "3"},
    {"Last 6 months", "6"},
    {"Last 12 months", "12"},
    {"Last 24 months", "24"},
    {"All time", "all"}
  ]
  @range_keys Enum.map(@range_options, &elem(&1, 1))
  @default_range_key "6"

  @impl Phoenix.LiveView
  def mount(%{"book_id" => book_id}, _session, socket) do
    with :ok <- Tracking.open_book(book_id),
         %Book{} = book <- Tracking.get_book(book_id) do
      if connected?(socket), do: Tracking.subscribe(book_id)

      socket
      |> assign(book: book, page_title: book.name, stale?: false)
      |> ok()
    else
      _ ->
        socket
        |> redirect_missing("That book could not be found.")
        |> ok()
    end
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    # The range lives in the URL, so both the initial mount and a select change (a
    # `push_patch`) flow through here and (re)start the async compute.
    socket
    |> assign(range_key: range_key(params))
    |> load_report()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} window_title={@book.name}>
      <div class="relative flex h-full flex-col overflow-hidden">
        <div class="flex items-center gap-3 border-b border-surface-200 px-4 py-3">
          <.link
            navigate={~p"/books/#{@book.id}"}
            class="inline-flex items-center gap-1 text-sm text-surface-600 transition-colors hover:text-primary-800"
          >
            <.icon name="hero-chevron-left" class="h-4 w-4" /> Expenses
          </.link>
          <h1 class="text-sm font-semibold text-surface-800">Report</h1>
          <form id="report-range-form" phx-change="change_range" class="ml-auto">
            <Bond.select
              name="range"
              value={@range_key}
              include_blank={false}
              options={@range_options}
              class="w-44"
              aria-label="Time range"
            />
          </form>
        </div>

        <div
          :if={@stale?}
          class="flex items-center gap-3 border-b border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-800"
        >
          <.icon name="hero-exclamation-triangle" class="h-4 w-4 shrink-0" />
          <span class="flex-1">This report may be out of date.</span>
          <Bond.button variant={:outline} phx-click="refresh">Refresh</Bond.button>
        </div>

        <.async_result :let={report} assign={@report}>
          <:loading>
            <Bond.loading_state message="Building your report…" />
          </:loading>
          <:failed :let={_reason}>
            <div class="m-4 flex flex-col items-center gap-3 rounded-lg px-6 py-12 text-center">
              <.icon name="hero-exclamation-circle" class="size-6 text-surface-400" />
              <p class="text-sm font-medium text-surface-700">Couldn't build the report.</p>
              <Bond.button variant={:outline} phx-click="refresh">Retry</Bond.button>
            </div>
          </:failed>

          <Bond.empty_state
            :if={report.empty?}
            message="No expenses yet"
            hint="Add expenses and they'll show up here, grouped by category and month."
          />
          <Bond.report_matrix :if={not report.empty?} report={report} />
        </.async_result>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("change_range", %{"range" => key}, socket) do
    # Persist the range in the URL; `handle_params` reloads for the new span.
    socket
    |> push_patch(
      to: ~p"/books/#{socket.assigns.book.id}/report?range=#{range_key(%{"range" => key})}"
    )
    |> noreply()
  end

  def handle_event("refresh", _params, socket) do
    socket
    |> load_report()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info({:book_updated, id}, socket) do
    case Tracking.get_book(id) do
      %Book{} = book ->
        # The Report is not recomputed here (ADR 0022) — just flagged stale. The title
        # still follows a rename live, and the native title bar is pushed to match.
        DesktopShell.set_book_title(book)

        socket
        |> assign(book: book, page_title: book.name, stale?: true)
        |> noreply()

      nil ->
        socket
        |> redirect_missing("This book was deleted.")
        |> noreply()
    end
  end

  # Category commands also emit `:categories_updated`, but they emit `:book_updated`
  # too, which already marks the Report stale — so ignore the redundant signal.
  def handle_info({:categories_updated, _id}, socket), do: noreply(socket)

  # Kicks off (or restarts) the async compute for the current range, clearing the
  # stale flag: the result about to load reflects the latest data. The work runs off
  # the LiveView process so a large fold never blocks first paint or the message loop.
  defp load_report(socket) do
    book_id = socket.assigns.book.id
    range = domain_range(socket.assigns.range_key)

    socket
    |> assign(stale?: false, range_options: @range_options)
    |> assign_async(:report, fn ->
      case Tracking.report(book_id, range: range) do
        {:error, reason} -> {:error, reason}
        report -> {:ok, %{report: ReportPresenter.to_view_model(report)}}
      end
    end)
  end

  # A recognized preset key from the URL, or the default; guards against a hand-typed
  # `?range=nonsense`.
  defp range_key(%{"range" => key}) when key in @range_keys, do: key
  defp range_key(_params), do: @default_range_key

  defp domain_range("all"), do: :all
  defp domain_range(key), do: {:trailing_months, String.to_integer(key)}

  defp redirect_missing(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/library")
  end
end
