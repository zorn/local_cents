defmodule Storybook.Elements.EmptyState do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.EmptyState.empty_state/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :message_and_hint,
        description: "A message with a quieter hint line pointing at the first action.",
        attributes: %{
          message: "No categories yet",
          hint: "Add one to start grouping your expenses."
        }
      },
      %Variation{
        id: :message_only,
        description: "Just the message, with no supporting hint.",
        attributes: %{
          message: "No expenses yet"
        }
      }
    ]
  end
end
