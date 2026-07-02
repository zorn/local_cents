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
            <LocalCentsWeb.Bond.Elements.Input.input type="search" placeholder="search..." class="flex-1" />
          </:leading_content>
          """,
          """
          <:trailing_content>
            <LocalCentsWeb.Bond.Elements.ActionChip.action_chip label="Tags" />
            <LocalCentsWeb.Bond.Elements.ActionChip.action_chip label="Newest" />
          </:trailing_content>
          """
        ]
      }
    ]
  end
end
