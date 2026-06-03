defmodule LocalCents.Tracking do
  @moduledoc """
  Provides functions for creating `Book` documents and the managing the `Expense` entries within books.
  """

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.ExAutomerge
  alias LocalCents.Tracking.Expense

  @spec new_book() :: Book.t()
  def new_book do
    ExAutomerge.new_document()
  end

  @spec add_expense(Book.t(), Expense.t()) :: Book.t()
  def add_expense(book, %Expense{description: description, amount: amount}) do
    ExAutomerge.add_expense(book, description, amount)
  end

  @spec list_expenses(Book.t()) :: [Expense.t()]
  def list_expenses(book) do
    book
    |> ExAutomerge.list_expenses()
    |> Enum.map(fn %{description: description, amount: amount} ->
      %Expense{description: description, amount: amount}
    end)
  end

  @spec merge(Book.t(), Book.t()) :: Book.t()
  def merge(left_book, right_book) do
    ExAutomerge.merge(left_book, right_book)
  end
end
