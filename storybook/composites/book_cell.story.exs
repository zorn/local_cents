defmodule Storybook.Composites.BookCell do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.BookCell.book_cell/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "A single book row with name and last updated subtitle.",
        attributes: %{
          name: "Family Expenses",
          last_updated: "06-02-2026 1:34 PM"
        }
      },
      %Variation{
        id: :long_name,
        description: "A book with a longer name that may truncate.",
        attributes: %{
          name: "Side Hustle LLC Expenses",
          last_updated: "05-15-2026 9:00 AM"
        }
      }
    ]
  end
end
