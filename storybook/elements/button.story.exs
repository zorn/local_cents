defmodule Storybook.Elements.Button do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.Button.button/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :primary,
        description: "Filled blue button for primary actions.",
        attributes: %{variant: :primary},
        slots: ["New Expense"]
      },
      %Variation{
        id: :outline,
        description: "Bordered button for secondary actions.",
        attributes: %{variant: :outline},
        slots: ["Open"]
      },
      %Variation{
        id: :square,
        description: "Small fixed-size square button for single characters.",
        attributes: %{variant: :square},
        slots: ["?"]
      },
      %Variation{
        id: :danger,
        description:
          "Borderless red text button for a destructive action (tuned for dark panels).",
        attributes: %{variant: :danger},
        slots: ["Delete"]
      },
      %Variation{
        id: :disabled,
        description: "Disabled state — dimmed, not-allowed cursor, and no stamp press on hover.",
        attributes: %{variant: :primary, disabled: true},
        slots: ["Create"]
      }
    ]
  end
end
