defmodule LocalCentsWeb.Bond do
  @moduledoc "Top-level facade for the Bond component library."

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
