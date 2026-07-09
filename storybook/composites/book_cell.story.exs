defmodule Storybook.Composites.BookCell do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.BookCell.book_cell/1
  def render_source, do: :function

  @actions """
  <:actions>
    <LocalCentsWeb.Bond.Elements.Button.button variant={:square}>
      <LocalCentsWeb.CoreComponents.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
    </LocalCentsWeb.Bond.Elements.Button.button>
    <LocalCentsWeb.Bond.Elements.Button.button variant={:outline}>Open</LocalCentsWeb.Bond.Elements.Button.button>
  </:actions>
  """

  def variations do
    [
      %Variation{
        id: :default,
        description: "A book row with an overflow menu and an Open button.",
        attributes: %{name: "Family Expenses"},
        slots: [@actions]
      },
      %Variation{
        id: :long_name,
        description: "A book with a longer name that may truncate.",
        attributes: %{name: "Side Hustle LLC Expenses"},
        slots: [@actions]
      }
    ]
  end
end
