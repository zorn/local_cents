defmodule Bond do
  @moduledoc "Top-level facade for the Bond component library."

  defdelegate action_chip(assigns), to: Bond.Elements.ActionChip
  defdelegate button(assigns), to: Bond.Elements.Button
  defdelegate checkbox(assigns), to: Bond.Elements.Checkbox
  defdelegate input(assigns), to: Bond.Elements.Input
  defdelegate list_view(assigns), to: Bond.Elements.ListView
  defdelegate desktop_window(assigns), to: Bond.Layouts.DesktopWindow
  defdelegate input_bar(assigns), to: Bond.Layouts.InputBar
  defdelegate list_controls(assigns), to: Bond.Layouts.ListControls
  defdelegate side_panel(assigns), to: Bond.Layouts.SidePanel
  defdelegate book_cell(assigns), to: Bond.Composites.BookCell
  defdelegate expense_cell(assigns), to: Bond.Composites.ExpenseCell
  defdelegate tag_pill(assigns), to: Bond.Elements.TagPill
end
