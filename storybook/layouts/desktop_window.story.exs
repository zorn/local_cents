defmodule Storybook.Layouts.DesktopWindow do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Layouts.DesktopWindow.desktop_window/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{},
        slots: [
          "This is the content of the window."
        ]
      }
    ]
  end
end
