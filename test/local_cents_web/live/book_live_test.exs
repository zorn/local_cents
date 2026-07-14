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

  test "shows the book's name in a draggable title bar", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/books/#{book.id}")
    |> assert_has("[data-tauri-drag-region]", text: "Family Expenses")
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

  describe "expense list" do
    test "shows an empty state before any expense exists", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("p", text: "No expenses yet")
    end

    test "lists a book's expenses, newest first", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      {:ok, _} =
        Tracking.add_expense(book.id, %{
          date: ~D[2026-05-01],
          description: "Older coffee",
          cost: "3"
        })

      {:ok, _} =
        Tracking.add_expense(book.id, %{
          date: ~D[2026-06-01],
          description: "Newer lunch",
          cost: "12.5"
        })

      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("#expenses", text: "Newer lunch")
      |> assert_has("#expenses", text: "$12.50")
      |> assert_has("#expenses", text: "Older coffee")
      # Sorted by date, newest first. Each expense row renders as a <button>, so
      # `#expenses button` selects the rows in document order; `at:` pins which one
      # (1-indexed) must carry which text — the June row before the May row.
      |> assert_has("#expenses button", at: 1, text: "Newer lunch")
      |> assert_has("#expenses button", at: 2, text: "Older coffee")
    end
  end

  describe "full editor" do
    test "adding an expense through the editor lists it", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("New Expense")
      |> within("#expense-editor", fn editor ->
        editor
        |> fill_in("Date", with: "2026-06-10")
        |> fill_in("Description", with: "Coffee")
        |> fill_in("Cost", with: "4.75")
        |> click_button("Create")
      end)
      |> assert_has("#expenses", text: "Coffee")
      |> assert_has("#expenses", text: "$4.75")
    end

    test "editing an expense through the editor updates it", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      {:ok, _} =
        Tracking.add_expense(book.id, %{
          date: ~D[2026-06-01],
          description: "Cofee typo",
          cost: "4"
        })

      conn
      |> visit(~p"/books/#{book.id}")
      |> within("#expenses", fn list -> click_button(list, "Cofee typo") end)
      |> within("#expense-editor", fn editor ->
        editor
        |> fill_in("Description", with: "Coffee")
        |> fill_in("Cost", with: "4.50")
        |> click_button("Save")
      end)
      |> assert_has("#expenses", text: "Coffee")
      |> assert_has("#expenses", text: "$4.50")
      |> refute_has("#expenses", text: "Cofee typo")
    end

    test "deleting an expense behind a confirmation removes it", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      {:ok, _} =
        Tracking.add_expense(book.id, %{
          date: ~D[2026-06-01],
          description: "Mistake",
          cost: "9.99"
        })

      conn
      |> visit(~p"/books/#{book.id}")
      |> within("#expenses", fn list -> click_button(list, "Mistake") end)
      |> within("#expense-editor", fn editor -> click_button(editor, "Delete") end)
      |> within("#delete-expense-modal", fn modal -> click_button(modal, "Delete") end)
      |> refute_has("#expenses", text: "Mistake")
      |> assert_has("p", text: "No expenses yet")
    end

    test "an expense with a blank description shows a validation error", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("New Expense")
      |> within("#expense-editor", fn editor ->
        editor
        |> fill_in("Cost", with: "5.00")
        |> click_button("Create")
      end)
      |> assert_has("#expense-editor", text: "can't be blank")
    end
  end

  describe "category selection" do
    test "filing a new expense under a category shows its badge in the list", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("New Expense")
      |> within("#expense-editor", fn editor ->
        editor
        |> fill_in("Date", with: "2026-06-10")
        |> fill_in("Description", with: "Whole Foods")
        |> fill_in("Cost", with: "42.00")
        |> select("Category", option: "Groceries")
        |> click_button("Create")
      end)
      |> assert_has("#expenses", text: "Whole Foods")
      |> assert_has("#expenses", text: "Groceries")
    end

    test "editing an expense files it under a category", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})

      {:ok, _} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "Milk", cost: "3"})

      conn
      |> visit(~p"/books/#{book.id}")
      |> within("#expenses", fn list -> click_button(list, "Milk") end)
      |> within("#expense-editor", fn editor ->
        editor
        |> select("Category", option: "Groceries")
        |> click_button("Save")
      end)
      |> assert_has("#expenses", text: "Groceries")
    end

    test "editing an expense reassigns it from one category to another", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, groceries} = Tracking.add_category(book.id, %{name: "Groceries"})
      {:ok, _transit} = Tracking.add_category(book.id, %{name: "Transit"})

      {:ok, expense} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "Milk", cost: "3"})

      {:ok, _} = Tracking.assign_category(book.id, expense.id, groceries.id)

      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("#expenses", text: "Groceries")
      |> within("#expenses", fn list -> click_button(list, "Milk") end)
      |> within("#expense-editor", fn editor ->
        editor
        |> select("Category", option: "Transit")
        |> click_button("Save")
      end)
      |> assert_has("#expenses", text: "Transit")
      |> refute_has("#expenses", text: "Groceries")
    end

    test "editing an expense unassigns its category via the blank option", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, groceries} = Tracking.add_category(book.id, %{name: "Groceries"})

      {:ok, expense} =
        Tracking.add_expense(book.id, %{date: ~D[2026-06-01], description: "Milk", cost: "3"})

      {:ok, _} = Tracking.assign_category(book.id, expense.id, groceries.id)

      conn
      |> visit(~p"/books/#{book.id}")
      |> assert_has("#expenses", text: "Groceries")
      |> within("#expenses", fn list -> click_button(list, "Milk") end)
      |> within("#expense-editor", fn editor ->
        editor
        |> select("Category", option: "")
        |> click_button("Save")
      end)
      |> refute_has("#expenses", text: "Groceries")
    end

    test "the editor shows a hint, not a picker, when the book has no categories", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("New Expense")
      |> assert_has("#expense-editor", text: "No categories yet")
      |> refute_has("#expense-editor label", text: "Category")
    end

    test "a category added elsewhere appears live in the open editor's picker", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      session =
        conn
        |> visit(~p"/books/#{book.id}")
        |> click_button("New Expense")
        |> assert_has("#expense-editor", text: "No categories yet")

      {:ok, _} = Tracking.add_category(book.id, %{name: "Groceries"})

      assert_has(session, "#expense-editor option", text: "Groceries", timeout: 100)
    end
  end
end
