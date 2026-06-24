defmodule Storybook.Elements.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Elements.Input.input/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{}
      },
      %Variation{
        id: :with_static_value,
        attributes: %{
          value: "some-value"
        }
      },
      %Variation{
        id: :with_placeholder,
        attributes: %{
          placeholder: "Enter your name"
        }
      }
    ]
  end
end
