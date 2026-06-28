defmodule Storybook.Elements.ActionChip do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Elements.ActionChip.action_chip/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :filter,
        description: "A chip that triggers a filter dropdown.",
        attributes: %{label: "Tags"}
      },
      %Variation{
        id: :sort,
        description: "A chip that triggers a sort dropdown.",
        attributes: %{label: "↕ Newest"}
      }
    ]
  end
end
