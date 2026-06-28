defmodule Storybook.Layouts.InputBar do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Layouts.InputBar.input_bar/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "A Bond.input and Bond.button as leading and trailing content.",
        slots: [
          """
          <:leading_content>
            <Bond.Elements.Input.input
              placeholder="coffee 4.75 or netflix 22.99 yesterday"
              class="flex-1"
            />
          </:leading_content>
          """,
          """
          <:trailing_content>
            <Bond.Elements.Button.button>New Expense</Bond.Elements.Button.button>
          </:trailing_content>
          """
        ]
      },
      %Variation{
        id: :short_prompt,
        description: "A shorter placeholder and terse button label.",
        slots: [
          """
          <:leading_content>
            <Bond.Elements.Input.input
              placeholder="Add an item..."
              class="flex-1"
            />
          </:leading_content>
          """,
          """
          <:trailing_content>
            <Bond.Elements.Button.button>Add</Bond.Elements.Button.button>
          </:trailing_content>
          """
        ]
      }
    ]
  end
end
