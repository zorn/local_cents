defmodule LocalCentsWeb.BookLiveTest do
  use LocalCentsWeb.FeatureCase, async: true

  import LocalCents.BooksDirHelper
  import LocalCents.SyncTestHelper

  alias LocalCents.Tracking

  @moduletag :tmp_dir

  setup :with_async_books_dir

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

  # On the desktop this view is its own native window, so there is nothing to go back
  # to; in a browser it is a page, and the title bar carries the way out (ADR 0023).
  test "the desktop title bar offers no way back", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/books/#{book.id}")
    |> refute_has("a", text: "Library")
  end

  test "the browser title bar links back to the library", ~M{conn} do
    {:ok, book} = Tracking.create_book("Family Expenses")

    conn
    |> browser_conn()
    |> visit(~p"/books/#{book.id}")
    |> click_link("Library")
    |> assert_path(~p"/library")
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

  describe "quick-add" do
    test "a line with a trailing amount lists the expense", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> fill_in("Quick add expense", with: "coffee 4.75")
      |> submit()
      |> assert_has("#expenses", text: "coffee")
      |> assert_has("#expenses", text: "$4.75")
    end

    test "a line with no amount lists a needs-amount expense", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> fill_in("Quick add expense", with: "coffee")
      |> submit()
      |> assert_has("#expenses", text: "coffee")
      # A nil cost renders as an em dash, not a faked $0.00 (ADR 0008).
      |> assert_has("#expenses", text: "—")
    end

    test "the field clears after a successful add, ready for the next line", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> fill_in("Quick add expense", with: "coffee 4.75")
      |> assert_has("#quick-add-input[value='coffee 4.75']")
      |> submit()
      |> assert_has("#quick-add-input[value='']")
    end

    test "a blank submit adds nothing", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> fill_in("Quick add expense", with: "   ")
      |> submit()
      |> assert_has("p", text: "No expenses yet")
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

  describe "synced conflict signal" do
    test "a conflicting sync raises a bell badge with the conflict count", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      # No signal while the book is quiet.
      session =
        conn
        |> visit(~p"/books/#{book.id}")
        |> refute_has("#conflict-bell")

      # A second peer forks the book, then both retitle the same expense while their
      # link is down — a scalar conflict LocalCents auto-resolves but must surface.
      peer_b = fork_peer(tmp_dir, book.id)
      {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})
      {:ok, _} = Tracking.edit_expense(peer_b, coffee.id, %{description: "Latte"})

      reconcile(book.id, peer_b)

      # The bell appears in the header with a badge of one, labeled for assistive tech,
      # and the expense list stays clean — the signal is never a per-row marker.
      session
      |> assert_has("#conflict-bell", text: "Synced changes", timeout: 100)
      |> assert_has("#conflict-bell", text: "1")
      |> assert_has("#expense-#{coffee.id}")
      |> refute_has("#expenses #conflict-bell")
    end

    test "opening the bell shows the Synced changes popup, and a row opens the editor",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      peer_b = fork_peer(tmp_dir, book.id)
      {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})
      {:ok, _} = Tracking.edit_expense(peer_b, coffee.id, %{description: "Latte"})
      reconcile(book.id, peer_b)

      # Automerge picks the winner; the popup row names whichever value it kept.
      %{field_conflicts: [conflict]} = Tracking.conflict_summary(book.id)
      kept = conflict.kept.value

      # The popup's copy must name LocalCents and never the sync internals (#237).
      session =
        session
        |> assert_has("#conflict-bell", timeout: 100)
        |> refute_has("#synced-changes-popup")
        |> click_button("Synced changes")

      session
      |> assert_has("#synced-changes-popup", text: "Auto-resolved")
      |> assert_has("#synced-changes-popup", text: "LocalCents kept one")
      |> refute_has("#synced-changes-popup", text: "Automerge")

      # Opening a row closes the popup behind it as the editor slides in.
      session
      |> within("#synced-changes-popup", fn popup -> click_button(popup, kept) end)
      |> assert_has("#expense-editor")
      |> assert_has("#expense-editor input[value='#{kept}']")
      |> refute_has("#synced-changes-popup")
    end

    test "an edit-vs-delete-only signal opens a popup with no empty Auto-resolved group",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      # One peer deletes the expense while this side edits it: the delete wins, but this
      # side's dropped edit surfaces as an edit-vs-delete conflict with no scalar conflict.
      peer_b = fork_peer(tmp_dir, book.id)
      {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})
      :ok = Tracking.delete_expense(peer_b, coffee.id)
      reconcile(book.id, peer_b)

      # The badge counts the dropped edit, but the popup shows no "Auto-resolved" group —
      # its label would otherwise head an empty list. Dismiss all still clears the signal.
      session
      |> assert_has("#conflict-bell", text: "1", timeout: 100)
      |> click_button("Synced changes")
      |> assert_has("#synced-changes-popup")
      |> refute_has("#synced-changes-popup", text: "Auto-resolved")
      |> within("#synced-changes-popup", fn popup -> click_button(popup, "Dismiss all") end)
      |> refute_has("#conflict-bell")
    end

    test "Dismiss all clears the signal and the badge", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      peer_b = fork_peer(tmp_dir, book.id)
      {:ok, _} = Tracking.edit_expense(book.id, coffee.id, %{description: "Espresso"})
      {:ok, _} = Tracking.edit_expense(peer_b, coffee.id, %{description: "Latte"})
      reconcile(book.id, peer_b)

      session
      |> assert_has("#conflict-bell", timeout: 100)
      |> click_button("Synced changes")
      |> within("#synced-changes-popup", fn popup -> click_button(popup, "Dismiss all") end)
      |> refute_has("#conflict-bell")
      |> refute_has("#synced-changes-popup")
    end
  end
end
