defmodule LocalCentsWeb.BookCategoriesLiveTest do
  # Not async: opening Books uses the global :books_dir env.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking

  setup :with_temp_books_dir

  describe "navigation" do
    test "reaches the categories page from the document window and back", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("Categories")
      |> assert_path(~p"/books/#{book.id}/categories")
      |> assert_has("h1", text: "Categories")
      |> click_link("Expenses")
      |> assert_path(~p"/books/#{book.id}")
      |> assert_has("h1", text: "Family Expenses")
    end

    test "an unknown book redirects to the library", ~M{conn} do
      conn
      |> visit(~p"/books/does-not-exist/categories")
      |> assert_path(~p"/library")
      |> assert_has("h1", text: "Library")
    end

    test "deleting the book closes the page to the library with a notice", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      session =
        conn
        |> visit(~p"/books/#{book.id}/categories")
        |> assert_has("h1", text: "Categories")

      :ok = Tracking.delete_book(book.id)

      session
      |> assert_has("h1", text: "Library", timeout: 100)
      |> assert_has("#flash-error", text: "This book was deleted.")
      |> assert_path(~p"/library")
    end
  end

  describe "empty state" do
    test "shows an empty state before any category exists", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> assert_has("p", text: "No categories yet")
    end
  end

  describe "adding" do
    test "adds a category and lists it", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("New Category")
      |> fill_in("Category name", with: "Groceries")
      |> click_button("Create")
      |> assert_has("#categories", text: "Groceries")
      |> refute_has("p", text: "No categories yet")
    end

    test "keeps the add row open so several can be added in a row", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("New Category")
      |> fill_in("Category name", with: "Groceries")
      |> click_button("Create")
      |> assert_has("#categories", text: "Groceries")
      |> fill_in("Category name", with: "Rent")
      |> click_button("Create")
      |> assert_has("#categories", text: "Rent")
      |> assert_has("#categories", text: "Groceries")
    end

    test "a blank name shows a validation error and stays in edit mode", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("New Category")
      |> fill_in("Category name", with: "")
      |> click_button("Create")
      |> assert_has("#categories", text: "can't be blank")
    end

    test "lists categories alphabetically, case-insensitively", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Rent"})
      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})
      {:ok, _} = Tracking.add_category(book.id, %{name: "auto"})

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> assert_has("#categories div[id^='category-row-']", at: 1, text: "auto")
      |> assert_has("#categories div[id^='category-row-']", at: 2, text: "Groceries")
      |> assert_has("#categories div[id^='category-row-']", at: 3, text: "Rent")
    end
  end

  describe "expense counts" do
    test "shows a per-category expense count", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})

      {:ok, one} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "A", cost: "1"})

      {:ok, two} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-02], description: "B", cost: "2"})

      {:ok, _} = Tracking.assign_category(book.id, one.id, category.id)
      {:ok, _} = Tracking.assign_category(book.id, two.id, category.id)

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> assert_has("#categories", text: "2 expenses")
    end

    test "renders a single expense in the singular", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, category} = Tracking.add_category(book.id, %{name: "Rent"})

      {:ok, expense} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "A", cost: "1"})

      {:ok, _} = Tracking.assign_category(book.id, expense.id, category.id)

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> assert_has("#categories", text: "1 expense")
    end

    test "renders a category with no expenses as 'No expenses'", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Travel"})

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> assert_has("#categories", text: "No expenses")
    end
  end

  describe "renaming" do
    test "renames a category inline", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Grocries"})

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("Rename Grocries")
      |> fill_in("Category name", with: "Groceries")
      |> click_button("Save")
      |> assert_has("#categories", text: "Groceries")
      |> refute_has("#categories", text: "Grocries")
    end

    test "renaming to a blank name shows an error and keeps the category", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})

      # A blank Save keeps the row in edit mode with the error; the category itself
      # is untouched, so canceling the edit restores its name.
      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("Rename Groceries")
      |> fill_in("Category name", with: "")
      |> click_button("Save")
      |> assert_has("#categories", text: "can't be blank")
      |> click_button("Cancel")
      |> assert_has("#categories", text: "Groceries")
    end
  end

  describe "deleting" do
    test "deleting a category with expenses un-files them behind a confirmation", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, category} = Tracking.add_category(book.id, %{name: "Groceries"})

      {:ok, expense} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "A", cost: "1"})

      {:ok, _} = Tracking.assign_category(book.id, expense.id, category.id)

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("Delete Groceries")
      |> assert_has("#delete-category-modal", text: "become Uncategorized")
      |> assert_has("#delete-category-modal", text: "1 expense")
      |> within("#delete-category-modal", fn modal -> click_button(modal, "Delete") end)
      |> refute_has("#categories", text: "Groceries")
      |> assert_has("p", text: "No categories yet")
    end

    test "deleting an empty category still asks for confirmation", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Travel"})

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("Delete Travel")
      |> assert_has("#delete-category-modal", text: "can't be undone")
      |> within("#delete-category-modal", fn modal -> click_button(modal, "Delete") end)
      |> refute_has("#categories", text: "Travel")
    end

    test "canceling a delete keeps the category", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Travel"})

      conn
      |> visit(~p"/books/#{book.id}/categories")
      |> click_button("Delete Travel")
      |> within("#delete-category-modal", fn modal -> click_button(modal, "Cancel") end)
      |> assert_has("#categories", text: "Travel")
    end
  end

  describe "live updates" do
    test "a category added elsewhere appears live", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      session =
        conn
        |> visit(~p"/books/#{book.id}/categories")
        |> assert_has("p", text: "No categories yet")

      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})

      assert_has(session, "#categories", text: "Groceries", timeout: 100)
    end
  end
end
