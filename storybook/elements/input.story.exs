defmodule Storybook.Elements.Input do
  use LocalCentsWeb.Storybook.Story, :component

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
        id: :with_label,
        description: "Input with a label rendered above it.",
        attributes: %{
          label: "Email",
          placeholder: "you@example.com"
        }
      },
      %Variation{
        id: :with_errors,
        description: "Input with a label and validation errors.",
        attributes: %{
          label: "Email",
          placeholder: "you@example.com",
          errors: ["can't be blank"]
        }
      },
      %Variation{
        id: :search,
        description: "Pill-shaped search field with magnifying glass icon.",
        attributes: %{type: "search", placeholder: "search..."}
      },
      %Variation{
        id: :frosted,
        description: "Frosted-blue variant for use inside dark panel backgrounds.",
        attributes: %{variant: "frosted", placeholder: "Enter value..."}
      },
      %Variation{
        id: :frosted_with_label,
        description: "Frosted variant with a label — typical usage inside the edit panel.",
        attributes: %{variant: "frosted", label: "Description", placeholder: "Enter value..."}
      }
    ]
  end
end
