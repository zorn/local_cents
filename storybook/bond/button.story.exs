defmodule Storybook.Bond.Button do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Button.button/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{},
        slots: [
          "Click me!"
        ]
      },
      %Variation{
        id: :disabled,
        attributes: %{
          disabled: true
        },
        slots: [
          "Click me!"
        ]
      }
    ]
  end
end
