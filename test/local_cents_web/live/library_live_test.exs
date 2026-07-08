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
    |> assert_has("li", text: "Family Expenses")
    |> assert_has("li", text: "Side Hustle")
  end

  test "creating a book adds it to the list", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> fill_in("New book name", with: "Groceries")
    |> click_button("Create")
    |> assert_has("li", text: "Groceries")
  end

  test "blank names are ignored", ~M{conn} do
    conn
    |> visit(~p"/library")
    |> fill_in("New book name", with: "   ")
    |> click_button("Create")
    |> refute_has("#books li")
  end

  test "opening a book keeps the library rendered", ~M{conn} do
    {:ok, _} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/library")
    |> click_button("Open")
    |> assert_has("h1", text: "Library")
  end
end
