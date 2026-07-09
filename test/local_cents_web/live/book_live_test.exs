defmodule LocalCentsWeb.BookLiveTest do
  # Not async: opening Books uses the global :books_dir env.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking

  setup :with_temp_books_dir

  test "shows the book's name", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/books/#{book.id}")
    |> assert_has("h1", text: "Family Expenses")
  end

  test "a renamed book updates the heading live", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    session =
      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("h1", text: "Family Expenses")

    :ok = Tracking.rename_book(book.id, "Household")

    assert_has(session, "h1", text: "Household")
  end

  test "an unknown book redirects to the library", ~M{conn} do
    conn
    |> visit(~p"/books/does-not-exist")
    |> assert_path(~p"/library")
    |> assert_has("h1", text: "Library")
  end

  test "deleting a book closes its open window to the library with a notice", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    session =
      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("h1", text: "Family Expenses")

    :ok = Tracking.delete_book(book.id)

    session
    |> assert_has("h1", text: "Library", timeout: 100)
    |> assert_has("#flash-error", text: "This book was deleted.")
    |> assert_path(~p"/library")
  end
end
