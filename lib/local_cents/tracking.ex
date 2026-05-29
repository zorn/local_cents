defmodule LocalCents.Tracking do
  @moduledoc """
  Provides functions for creating `Book` documents and the managing the `Expense` entries within books.
  """

  alias LocalCents.Tracking.Book
  alias LocalCents.Tracking.Expense

  @spec new_book() :: Book.t()
  def new_book() do
  end

  @spec add_expense(Book.t(), Expense.t()) :: Book.t()
  def add_expense(_book, _expense) do
  end

  @spec list_expenses(Book.t()) :: [Expense.t()]
  def list_expenses(_book) do
    []
  end
end
