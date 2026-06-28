defmodule Storybook.Composites.ExpenseCell do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Composites.ExpenseCell.expense_cell/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :with_tags,
        description: "Expense row with multiple tag pills.",
        attributes: %{
          date: "2025-06-15",
          description: "Whole Foods Market",
          amount: "$87.43",
          tags: [
            %{label: "groceries", color: "#3f7fd6"},
            %{label: "household", color: "#e6b53c"}
          ]
        }
      },
      %Variation{
        id: :no_tags,
        description: "Expense row with no tags.",
        attributes: %{
          date: "2025-06-18",
          description: "Netflix",
          amount: "$15.99",
          tags: []
        }
      }
    ]
  end
end
