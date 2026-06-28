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
        id: :with_placeholder,
        attributes: %{
          placeholder: "coffee 4.75 or netflix 22.99 yesterday"
        }
      },
      %Variation{
        id: :with_value,
        attributes: %{
          value: "Whole Foods $127.43"
        }
      },
      %Variation{
        id: :search,
        description: "Pill-shaped search field with magnifying glass icon.",
        attributes: %{type: "search", placeholder: "search..."}
      }
    ]
  end
end
