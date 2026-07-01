defmodule Storybook.Layouts.DesktopWindow do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Layouts.DesktopWindow.desktop_window/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "A window with a title and placeholder content.",
        attributes: %{
          title: "Family Expenses"
        },
        slots: [
          """
          <div style="width: 520px; padding: 16px;">
            Some content.
          </div>
          """
        ]
      }
    ]
  end
end
