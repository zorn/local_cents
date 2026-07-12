defmodule LocalCentsWeb.LibraryLiveTest do
  # Not async: creating Books uses the global :books_dir env.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking

  setup :with_temp_books_dir

  test "shows the window title in a draggable title bar", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> assert_has("[data-tauri-drag-region]", text: "Library")
  end

  test "lists existing books", ~M{conn} do
    {:ok, _} = Tracking.create_book("Family Expenses")
    {:ok, _} = Tracking.create_book("Side Hustle")

    conn
    |> visit(~p"/library")
    |> assert_has("#books", text: "Family Expenses")
    |> assert_has("#books", text: "Side Hustle")
  end

  test "shows a book's last updated subtitle", ~M{conn} do
    # No browser time zone is reported in tests, so the subtitle renders in UTC:
    # 13:34 UTC -> "1:34 PM".
    {:ok, _} = Tracking.create_book("Family Expenses", ~U[2026-06-02 13:34:20Z])

    conn
    |> visit(~p"/library")
    |> assert_has("#books", text: "Last Updated: 06-02-2026 1:34 PM")
  end

  test "keeps a book's last updated live when the book changes elsewhere", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family", ~U[2026-06-02 13:34:20Z])

    session =
      conn
      |> visit(~p"/library")
      |> assert_has("#books", text: "Last Updated: 06-02-2026 1:34 PM")

    # An edit from the Book's own document window broadcasts to the library.
    {:ok, _expense} =
      Tracking.add_expense(
        book.id,
        %{description: "Coffee", cost: "5.00"},
        ~U[2026-06-02 15:10:05Z]
      )

    assert_has(session, "#books", text: "Last Updated: 06-02-2026 3:10 PM")
  end

  test "shows an empty state before any book exists", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> assert_has("p", text: "No books yet")
  end

  test "the create form is revealed by New Book and hidden by Cancel", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> refute_has("#create-book-form")
    |> click_button("New Book")
    |> assert_has("#create-book-form")
    |> click_button("Cancel")
    |> refute_has("#create-book-form")
  end

  test "creating a book adds it to the list", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> click_button("New Book")
    |> fill_in("New book name", with: "Groceries")
    |> click_button("Create")
    |> assert_has("#books", text: "Groceries")
  end

  test "Create stays disabled until a non-blank name is entered", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> click_button("New Book")
    |> assert_has("button[disabled]", text: "Create")
    |> fill_in("New book name", with: "   ")
    |> assert_has("button[disabled]", text: "Create")
    |> fill_in("New book name", with: "Groceries")
    |> refute_has("button[disabled]", text: "Create")
  end

  test "opening a book keeps the library rendered", ~M{conn} do
    {:ok, _} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/library")
    |> click_button("Open")
    |> assert_has("h1", text: "Library")
  end

  test "renaming a book through the menu updates the list", ~M{conn} do
    {:ok, book} = Tracking.create_book("Old Name")

    session =
      conn
      |> visit(~p"/library")
      |> within("#book-#{book.id}", fn row -> click_button(row, "Rename") end)

    session
    |> within("#rename-modal", fn modal ->
      modal
      |> fill_in("New name", with: "New Name")
      |> click_button("Rename")
    end)
    |> assert_has("#books", text: "New Name")
    |> refute_has("#books", text: "Old Name")
  end

  test "renaming to a blank name shows a validation error", ~M{conn} do
    {:ok, book} = Tracking.create_book("Keep Me")

    conn
    |> visit(~p"/library")
    |> within("#book-#{book.id}", fn row -> click_button(row, "Rename") end)
    |> within("#rename-modal", fn modal ->
      modal
      |> fill_in("New name", with: "   ")
      |> click_button("Rename")
    end)
    |> assert_has("#rename-modal", text: "can't be blank")
  end

  test "deleting a book through the menu removes it from the list", ~M{conn} do
    {:ok, book} = Tracking.create_book("Doomed")

    conn
    |> visit(~p"/library")
    |> within("#book-#{book.id}", fn row -> click_button(row, "Delete") end)
    |> within("#delete-modal", fn modal -> click_button(modal, "Delete") end)
    |> assert_has("p", text: "No books yet")

    assert Tracking.list_books() == []
  end
end
