defmodule LocalCentsWeb.LibraryLiveTest do
  # Not async: creating Books uses the global :books_dir env.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking

  setup :with_temp_books_dir

  test "lists existing books", ~M{conn} do
    {:ok, _} = Tracking.create_book("Family Expenses")
    {:ok, _} = Tracking.create_book("Side Hustle")

    conn
    |> visit(~p"/library")
    |> assert_has("#books", text: "Family Expenses")
    |> assert_has("#books", text: "Side Hustle")
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

  test "a blank name shows a validation error and creates nothing", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> click_button("New Book")
    |> fill_in("New book name", with: "   ")
    |> click_button("Create")
    |> assert_has("p", text: "can't be blank")
    |> refute_has("#books")
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
      |> within("#book-#{book.id}", fn s ->
        s
        |> click_button("Book actions")
        |> click_button("Rename")
      end)

    session
    |> within("#rename-modal", fn s ->
      s
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
    |> within("#book-#{book.id}", fn s ->
      s
      |> click_button("Book actions")
      |> click_button("Rename")
    end)
    |> within("#rename-modal", fn s ->
      s
      |> fill_in("New name", with: "   ")
      |> click_button("Rename")
    end)
    |> assert_has("#rename-modal", text: "can't be blank")
  end

  test "deleting a book through the menu removes it from the list", ~M{conn} do
    {:ok, book} = Tracking.create_book("Doomed")

    conn
    |> visit(~p"/library")
    |> within("#book-#{book.id}", fn s ->
      s
      |> click_button("Book actions")
      |> click_button("Delete")
    end)
    |> within("#delete-modal", fn s -> click_button(s, "Delete") end)
    |> assert_has("p", text: "No books yet")

    assert Tracking.list_books() == []
  end
end
