# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
# This module is a pure delegation hub — one `defdelegate` per Bond component — so
# its dependency count grows with the library by design, like the other aggregator
# modules (e.g. `LocalCentsWeb`).
defmodule LocalCentsWeb.Bond do
  @moduledoc """
  The front door to Bond, LocalCents' hand-authored component library.

  Bond is the set of function components we build our screens from, written to
  replace the generic `phx.new` defaults in `LocalCentsWeb.CoreComponents` with
  a cohesive, on-brand look (see
  [ADR 0004](0004-remove-daisyui-hand-authored-components.html)). This module is
  the single entry point: it `defdelegate`s one function per component to its
  home module, so callers write `Bond.button/1` without needing to know or
  import the deeper module path.

  Prefer these over `CoreComponents` for new UI. Every component here has a
  matching Storybook story; browse the running catalog to see them rendered.

  ## Tiers

  Components are organized into three tiers by how much they know about the
  domain:

    * **Elements** (`LocalCentsWeb.Bond.Elements`) — the smallest building
      blocks, styled but domain-agnostic (buttons, inputs, list views).
    * **Layouts** (`LocalCentsWeb.Bond.Layouts`) — slot-driven arrangement
      shells that position content but carry no data of their own (the window
      shell, modals, side panels).
    * **Composites** (`LocalCentsWeb.Bond.Composites`) — domain-aware units that
      combine elements into a single view (the Book cell, the Report matrix).

  The `defdelegate` list below is the authoritative roster of each tier's
  components; this prose only sketches the tiers, so a new component needs no edit
  here.

  ## Usage

  `LocalCentsWeb.Bond` is aliased in `local_cents_web.ex`, so templates call
  the delegated functions directly:

      <Bond.button variant={:primary}>Save</Bond.button>
  """

  defdelegate button(assigns), to: LocalCentsWeb.Bond.Elements.Button
  defdelegate conflict_bell(assigns), to: LocalCentsWeb.Bond.Elements.ConflictBell
  defdelegate empty_state(assigns), to: LocalCentsWeb.Bond.Elements.EmptyState
  defdelegate loading_state(assigns), to: LocalCentsWeb.Bond.Elements.LoadingState
  defdelegate input(assigns), to: LocalCentsWeb.Bond.Elements.Input
  defdelegate list_view(assigns), to: LocalCentsWeb.Bond.Elements.ListView
  defdelegate menu(assigns), to: LocalCentsWeb.Bond.Elements.Menu
  defdelegate select(assigns), to: LocalCentsWeb.Bond.Elements.Select
  defdelegate debug_bar(assigns), to: LocalCentsWeb.Bond.Layouts.DebugBar
  defdelegate desktop_window(assigns), to: LocalCentsWeb.Bond.Layouts.DesktopWindow
  defdelegate input_bar(assigns), to: LocalCentsWeb.Bond.Layouts.InputBar
  defdelegate modal(assigns), to: LocalCentsWeb.Bond.Layouts.Modal
  defdelegate side_panel(assigns), to: LocalCentsWeb.Bond.Layouts.SidePanel
  defdelegate window_bar(assigns), to: LocalCentsWeb.Bond.Layouts.WindowBar
  defdelegate book_cell(assigns), to: LocalCentsWeb.Bond.Composites.BookCell
  defdelegate category_row(assigns), to: LocalCentsWeb.Bond.Composites.CategoryRow
  defdelegate expense_cell(assigns), to: LocalCentsWeb.Bond.Composites.ExpenseCell
  defdelegate expense_conflicts(assigns), to: LocalCentsWeb.Bond.Composites.ExpenseConflicts
  defdelegate report_matrix(assigns), to: LocalCentsWeb.Bond.Composites.ReportMatrix
  defdelegate synced_changes_popup(assigns), to: LocalCentsWeb.Bond.Composites.SyncedChangesPopup
end
