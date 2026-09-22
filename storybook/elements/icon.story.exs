defmodule Storybook.Elements.Icon do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.Icon.icon/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "Default size (size-4), outline style.",
        attributes: %{name: "hero-check-circle"}
      },
      %Variation{
        id: :solid,
        description: "Solid style via the -solid suffix.",
        attributes: %{name: "hero-check-circle-solid"}
      },
      %Variation{
        id: :sized,
        description: "Size comes from a utility class on `class`.",
        attributes: %{name: "hero-exclamation-circle", class: "size-8"}
      },
      %Variation{
        id: :colored,
        description: "Color comes from a text-color utility on `class`.",
        attributes: %{name: "hero-x-mark", class: "size-6 text-error-600"}
      },
      %Variation{
        id: :spinning,
        description: "Motion-safe spin, as used by the loading state.",
        attributes: %{name: "hero-arrow-path", class: "size-6 motion-safe:animate-spin"}
      }
    ]
  end
end
