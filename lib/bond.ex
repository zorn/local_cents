defmodule Bond do
  @moduledoc "Top-level facade for the Bond component library."

  defdelegate button(assigns), to: Bond.Elements.Button
  defdelegate input(assigns), to: Bond.Elements.Input
  defdelegate list_view(assigns), to: Bond.Elements.ListView
  defdelegate desktop_window(assigns), to: Bond.Layouts.DesktopWindow
  defdelegate input_bar(assigns), to: Bond.Layouts.InputBar
  defdelegate book_cell(assigns), to: Bond.Composites.BookCell
end
