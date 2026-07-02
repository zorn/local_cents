defmodule LocalCents.Tracking do
  @moduledoc """
  Provides functions for creating `Book` documents and the managing the `Expense` entries within books.

  This module is the public API for the tracking context. Call sites must go
  through it — the internal implementation (e.g. `ExAutomerge`) is not exported
  and may not be called from outside this boundary. Only the `Book` and
  `Expense` types are exported, since they make up the context's contract:
  `Expense` is a struct, and `Book` is an opaque `binary()` (a serialized
  Automerge document).
  """

  # The tracking context boundary. It is a top-level boundary (a peer of the
  # core and web layers rather than nested inside `LocalCents`) so that other
  # layers can depend on the context directly. It exports only the `Book` and
  # `Expense` types that make up its API contract; the implementation modules
  # stay private.
  use Boundary, top_level?: true, deps: [], exports: [Book, Expense]

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
