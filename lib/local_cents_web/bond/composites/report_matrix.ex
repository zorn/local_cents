defmodule LocalCentsWeb.Bond.Composites.ReportMatrix do
  @moduledoc """
  The **Report**'s Category × Month spending matrix, rendered as a frozen-frame
  spreadsheet grid (see [ADR 0020](0020-bounded-time-series-in-review.html) /
  [ADR 0021](0021-bounded-report-range.html)).

  A semantic `<table>` — the correct, accessible element for this genuinely tabular
  data — with a stable frame: the **Category** column freezes on the left, the
  lifetime/in-range **Total** column freezes on the right, the Month header sticks to
  the top and the column-total footer to the bottom, and the grand-total cell is
  pinned in the bottom-right corner. Only the Month cells scroll, so orientation is
  never lost on a wide Book.

  It is deliberately domain-agnostic: it takes the fully-formatted view model built by
  `LocalCentsWeb.ReportPresenter` — plain month labels and tagged cell shapes, never a
  `Decimal` or a `Month` — so all money/label formatting lives in one tested place.
  Each cell renders by its `kind` (`:money`, `:money_needs`, `:needs`, `:zero`); a
  needs-amount cell shows an amber count with a hover note explaining it, and is never
  drawn as `$0`. The caller renders the empty-Book state itself; this component assumes
  a populated report.
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :id, :string, default: "report-matrix"

  attr :report, :map,
    required: true,
    doc: "The formatted view model from `LocalCentsWeb.ReportPresenter.to_view_model/1`"

  @spec report_matrix(Socket.assigns()) :: Rendered.t()
  def report_matrix(assigns) do
    ~H"""
    <div id={@id} class="min-h-0 flex-1 overflow-auto bg-white">
      <table class="w-full border-separate border-spacing-0 text-sm tabular-nums">
        <thead>
          <tr>
            <th
              scope="col"
              class="sticky left-0 top-0 z-30 border-b border-r border-surface-300 bg-surface-100 px-3 py-2 text-left text-xs font-semibold text-surface-600"
            >
              Category
            </th>
            <th
              :for={month <- @report.months}
              scope="col"
              class="sticky top-0 z-20 border-b border-surface-200 bg-surface-100 px-3 py-2 text-right text-xs font-semibold text-surface-600 whitespace-nowrap"
            >
              {month.label}
            </th>
            <th
              scope="col"
              class="sticky right-0 top-0 z-30 border-b border-l border-surface-300 bg-surface-100 px-3 py-2 text-right text-xs font-semibold text-surface-700"
            >
              Total
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @report.rows} class="group">
            <th
              scope="row"
              class="sticky left-0 z-10 border-b border-r border-surface-200 bg-white px-3 py-2 text-left font-medium text-surface-800 whitespace-nowrap group-hover:bg-surface-50"
            >
              {row.name}
            </th>
            <td
              :for={cell <- row.cells}
              class="border-b border-surface-100 px-3 py-2 text-right group-hover:bg-surface-50"
            >
              <.cell cell={cell} />
            </td>
            <td class="sticky right-0 z-10 border-b border-l border-surface-200 bg-white px-3 py-2 text-right font-semibold text-surface-900 group-hover:bg-surface-50">
              <.cell cell={row.total} />
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr>
            <th
              scope="row"
              class="sticky bottom-0 left-0 z-30 border-t-2 border-r border-surface-300 bg-surface-100 px-3 py-2 text-left text-xs font-semibold text-surface-700"
            >
              Grand total
            </th>
            <td
              :for={total <- @report.column_totals}
              class="sticky bottom-0 z-20 border-t-2 border-surface-300 bg-surface-100 px-3 py-2 text-right font-semibold text-surface-800 tabular-nums"
            >
              <.cell cell={total} />
            </td>
            <td class="sticky bottom-0 right-0 z-40 border-t-2 border-l border-surface-300 bg-primary-50 px-3 py-2 text-right font-bold text-primary-900">
              <.cell cell={@report.grand_total} />
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  # One cell of the matrix, drawn by its kind. A needs-amount cell is never shown as
  # `$0` — its count is surfaced as a marker instead (see the moduledoc).
  attr :cell, :map, required: true

  defp cell(%{cell: %{kind: :money}} = assigns) do
    ~H|<span class="text-surface-800">{@cell.text}</span>|
  end

  defp cell(%{cell: %{kind: :money_needs}} = assigns) do
    ~H"""
    <span class="inline-flex items-center justify-end gap-1.5">
      <span class="text-surface-800">{@cell.text}</span>
      <.needs_marker count={@cell.count} />
    </span>
    """
  end

  defp cell(%{cell: %{kind: :needs}} = assigns) do
    ~H|<.needs_marker count={@cell.count} />|
  end

  defp cell(%{cell: %{kind: :zero}} = assigns) do
    ~H|<span class="text-surface-300">—</span>|
  end

  attr :count, :integer, required: true

  defp needs_marker(assigns) do
    assigns = assign(assigns, :note, needs_note(assigns.count))

    ~H"""
    <%!-- A CSS hover note rather than a native `title`: Tauri's WKWebView does not
    render `title` tooltips. Positioned above and right-aligned so it opens into the
    table body (away from the scroll container's clipped edges). --%>
    <span
      class="group/needs relative inline-flex cursor-default items-center gap-0.5 text-amber-600"
      aria-label={@note}
    >
      <.icon name="hero-exclamation-circle" class="size-3.5" />
      <span class="text-xs font-semibold">{@count}</span>
      <span class="pointer-events-none absolute bottom-full right-0 z-50 mb-1 hidden w-max max-w-xs whitespace-normal rounded-md bg-surface-900 px-2.5 py-1.5 text-left text-xs font-normal leading-snug text-white shadow-lg group-hover/needs:block">
        {@note}
      </span>
    </span>
    """
  end

  # The hover note that explains a needs-amount marker — what it is and why it shows.
  defp needs_note(1),
    do: "1 expense here doesn't have an amount entered yet — counted, but not added to the total."

  defp needs_note(count),
    do:
      "#{count} expenses here don't have an amount entered yet — counted, but not added to the total."
end
