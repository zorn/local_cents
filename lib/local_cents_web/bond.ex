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
      blocks, styled but domain-agnostic: `button/1`, `input/1`, `checkbox/1`,
      `action_chip/1`, `list_view/1`, `tag_pill/1`.
    * **Layouts** (`LocalCentsWeb.Bond.Layouts`) — slot-driven arrangement
      shells that position content but carry no data of their own:
      `desktop_window/1`, `input_bar/1`, `list_controls/1`, `side_panel/1`.
    * **Composites** (`LocalCentsWeb.Bond.Composites`) — domain-aware rows that
      combine elements into a single unit: `book_cell/1`, `expense_cell/1`.

  ## Usage

  `LocalCentsWeb.Bond` is aliased in `local_cents_web.ex`, so templates call
  the delegated functions directly:

      <Bond.button variant={:primary}>Save</Bond.button>
  """

  defdelegate action_chip(assigns), to: LocalCentsWeb.Bond.Elements.ActionChip
  defdelegate button(assigns), to: LocalCentsWeb.Bond.Elements.Button
  defdelegate checkbox(assigns), to: LocalCentsWeb.Bond.Elements.Checkbox
  defdelegate input(assigns), to: LocalCentsWeb.Bond.Elements.Input
  defdelegate list_view(assigns), to: LocalCentsWeb.Bond.Elements.ListView
  defdelegate desktop_window(assigns), to: LocalCentsWeb.Bond.Layouts.DesktopWindow
  defdelegate input_bar(assigns), to: LocalCentsWeb.Bond.Layouts.InputBar
  defdelegate list_controls(assigns), to: LocalCentsWeb.Bond.Layouts.ListControls
  defdelegate side_panel(assigns), to: LocalCentsWeb.Bond.Layouts.SidePanel
  defdelegate book_cell(assigns), to: LocalCentsWeb.Bond.Composites.BookCell
  defdelegate expense_cell(assigns), to: LocalCentsWeb.Bond.Composites.ExpenseCell
  defdelegate tag_pill(assigns), to: LocalCentsWeb.Bond.Elements.TagPill
end
