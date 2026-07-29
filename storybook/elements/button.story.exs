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
        id: :destructive,
        description: "Filled red button for a destructive action (e.g. a delete confirmation).",
        attributes: %{variant: :destructive},
        slots: ["Delete"]
      },
      %Variation{
        id: :disabled,
        description: "Disabled state — dimmed, not-allowed cursor, and no stamp press on hover.",
        attributes: %{variant: :primary, disabled: true},
        slots: ["Create"]
      },
      %Variation{
        id: :navigate,
        description:
          "Given `navigate`, the same button renders as a link — for an action that is " <>
            "really navigation, such as the library's Open in the browser client " <>
            "(ADR 0023). Identical to the eye, but hover it and the browser shows a URL.",
        attributes: %{variant: :outline, navigate: "/library"},
        slots: ["Open"]
      }
    ]
  end
end
