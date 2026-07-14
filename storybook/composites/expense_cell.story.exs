defmodule Storybook.Composites.ExpenseCell do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.ExpenseCell.expense_cell/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :categorized,
        description: "Expense row with a single category.",
        attributes: %{
          date: "06/15/2025",
          description: "Whole Foods Market",
          amount: "$87.43",
          category: %{label: "groceries", color: "#3f7fd6"}
        }
      },
      %Variation{
        id: :uncategorized,
        description: "Expense row with no category.",
        attributes: %{
          date: "06/18/2025",
          description: "Netflix",
          amount: "$15.99"
        }
      }
    ]
  end
end
