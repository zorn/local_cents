defmodule Storybook.Layouts.ListControls do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Layouts.ListControls.list_controls/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "Search input with filter and sort action buttons.",
        slots: [
          """
          <:leading_content>
            <Bond.Elements.Input.input type="search" placeholder="search..." class="flex-1" />
          </:leading_content>
          """,
          """
          <:trailing_content>
            <button style="display: flex; align-items: center; gap: 4px; padding: 6px 10px; font-size: 0.875rem; font-weight: 600; border-radius: 9999px;">
              Tags
            </button>
            <button style="display: flex; align-items: center; gap: 4px; padding: 6px 10px; font-size: 0.875rem; font-weight: 600; border-radius: 9999px;">
              ↕ Newest
            </button>
          </:trailing_content>
          """
        ]
      }
    ]
  end
end
