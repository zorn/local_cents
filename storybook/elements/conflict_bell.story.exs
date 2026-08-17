defmodule Storybook.Elements.ConflictBell do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.ConflictBell.conflict_bell/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :single,
        description: "One synced change needs attention.",
        attributes: %{count: 1}
      },
      %Variation{
        id: :many,
        description: "A large batch of synced changes.",
        attributes: %{count: 42}
      }
    ]
  end
end
