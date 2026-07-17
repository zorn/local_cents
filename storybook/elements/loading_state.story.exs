defmodule Storybook.Elements.LoadingState do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.LoadingState.loading_state/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :message_and_hint,
        description: "A working-on-it message with a quieter reassurance about the wait.",
        attributes: %{
          message: "Setting up your demo library…",
          hint: "This only happens the first time."
        }
      },
      %Variation{
        id: :message_only,
        description: "Just the message, with no supporting hint.",
        attributes: %{
          message: "Loading…"
        }
      }
    ]
  end
end
