defmodule Storybook.Elements.TagPill do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.TagPill.tag_pill/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :groceries,
        attributes: %{label: "groceries", color: "#3f7fd6"}
      },
      %Variation{
        id: :dining,
        attributes: %{label: "dining", color: "#6fc59a"}
      },
      %Variation{
        id: :kids,
        attributes: %{label: "kids", color: "#e6b53c"}
      },
      %Variation{
        id: :unknown,
        description: "Long label with the default fallback swatch color.",
        attributes: %{label: "some-long-tag-name", color: "#8b9fc0"}
      }
    ]
  end
end
