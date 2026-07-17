defmodule Storybook.Elements.Select do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Elements.Select.select/1
  def render_source, do: :function

  @options [{"Groceries", "c1"}, {"Transit", "c2"}, {"Rent", "c3"}]

  def variations do
    [
      %Variation{
        id: :default,
        description: "A select with a leading blank option and three choices.",
        attributes: %{options: @options}
      },
      %Variation{
        id: :with_label,
        description: "Select with a label rendered above it.",
        attributes: %{label: "Category", options: @options}
      },
      %Variation{
        id: :with_selection,
        description: "A value is pre-selected.",
        attributes: %{label: "Category", options: @options, value: "c2"}
      },
      %Variation{
        id: :without_blank,
        description: "No blank option — the first choice is selected by default.",
        attributes: %{label: "Sort", options: @options, include_blank: false}
      },
      %Variation{
        id: :with_errors,
        description: "Select with a label and validation errors.",
        attributes: %{label: "Category", options: @options, errors: ["can't be blank"]}
      },
      %Variation{
        id: :frosted_with_label,
        description:
          "Frosted variant with a label and an empty blank option — the expense editor's Category picker, where blank means Uncategorized.",
        attributes: %{variant: "frosted", label: "Category", options: @options}
      }
    ]
  end
end
