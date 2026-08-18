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

    test "opening the bell shows the Synced changes popup, and a row opens the Conflicts tab",
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

      # A popup row opens straight to that Expense's Conflicts tab — where the kept value is
      # shown — and closes the popup behind it as the editor slides in.
      session
      |> within("#synced-changes-popup", fn popup -> click_button(popup, kept) end)
      |> assert_has("#expense-conflicts", text: kept)
      |> refute_has("#synced-changes-popup")
    end

    test "an edit-vs-delete conflict opens a Needs your decision group, not an Auto-resolved one",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      seed_edit_delete_conflict(tmp_dir, book.id, coffee.id, "Espresso")

      # The dropped edit surfaces in the second group with its description, and no
      # "Auto-resolved" label heads an empty scalar list. The copy names LocalCents only.
      session =
        session
        |> assert_has("#conflict-bell", text: "1", timeout: 100)
        |> click_button("Synced changes")
        |> assert_has("#synced-changes-popup", text: "Needs your decision")
        |> assert_has("#synced-changes-popup", text: "Espresso")
        |> refute_has("#synced-changes-popup", text: "Auto-resolved")
        |> refute_has("#synced-changes-popup", text: "Automerge")

      # Dismiss all clears an edit-delete-only signal too, not just a scalar one — it drops
      # both groups of the summary, so the bell disappears.
      session
      |> within("#synced-changes-popup", fn popup -> click_button(popup, "Dismiss all") end)
      |> refute_has("#conflict-bell")
    end

    test "Keep deleted acknowledges just that dropped edit and updates the badge",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})
      {:ok, lunch} = Tracking.add_expense(book.id, %{description: "Lunch", cost: "9.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      seed_edit_delete_conflict(tmp_dir, book.id, [{coffee.id, "Espresso"}, {lunch.id, "Dinner"}])

      # Keeping the coffee delete clears its row and drops the badge to the lunch one.
      session
      |> assert_has("#conflict-bell", text: "2", timeout: 100)
      |> click_button("Synced changes")
      |> within("#needs-decision-#{coffee.id}", fn row -> click_button(row, "Keep deleted") end)
      |> assert_has("#conflict-bell", text: "1")
      |> refute_has("#synced-changes-popup", text: "Espresso")
      |> assert_has("#synced-changes-popup", text: "Dinner")
    end

    test "Restore revives the expense with its dropped edit and clears the signal",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      seed_edit_delete_conflict(tmp_dir, book.id, coffee.id, "Espresso")

      # The reconcile removed Coffee; Restore brings it back carrying the dropped edit, and
      # the last decision resolved so the bell disappears.
      session
      |> assert_has("#conflict-bell", text: "1", timeout: 100)
      |> refute_has("#expenses", text: "Coffee")
      |> click_button("Synced changes")
      |> within("#needs-decision-#{coffee.id}", fn row -> click_button(row, "Restore") end)
      |> refute_has("#conflict-bell")
      |> assert_has("#expenses", text: "Espresso")
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

  describe "editor Conflicts tab" do
    test "appears only for an expense with an unresolved conflict", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})
      {:ok, _tea} = Tracking.add_expense(book.id, %{description: "Tea", cost: "2.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      kept = seed_scalar_conflict(tmp_dir, book.id, coffee.id, "Espresso", "Latte")

      session = assert_has(session, "#conflict-bell", timeout: 100)

      session
      |> within("#expenses", fn list -> click_button(list, kept) end)
      |> assert_has("#expense-editor button", text: "Conflicts")

      # An untouched expense's editor has no tabs at all.
      session
      |> within("#expenses", fn list -> click_button(list, "Tea") end)
      |> refute_has("#expense-editor button", text: "Conflicts")
    end

    test "shows the kept value and each dropped alternative with provenance",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      kept = seed_scalar_conflict(tmp_dir, book.id, coffee.id, "Espresso", "Latte")
      dropped = if kept == "Espresso", do: "Latte", else: "Espresso"
      year = to_string(Date.utc_today().year)

      session
      |> assert_has("#conflict-bell", timeout: 100)
      |> within("#expenses", fn list -> click_button(list, kept) end)
      |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)
      |> assert_has("#expense-conflicts", text: "Kept by LocalCents")
      |> assert_has("#expense-conflicts", text: kept)
      |> assert_has("#expense-conflicts", text: dropped)
      # Provenance: which device made the edit (a stable token) and when.
      |> assert_has("#expense-conflicts", text: "Device")
      |> assert_has("#expense-conflicts", text: year)
    end

    test "Make this the value overrides to the alternative and clears the tab and badge",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      kept = seed_scalar_conflict(tmp_dir, book.id, coffee.id, "Espresso", "Latte")
      dropped = if kept == "Espresso", do: "Latte", else: "Espresso"

      session =
        session
        |> assert_has("#conflict-bell", timeout: 100)
        |> within("#expenses", fn list -> click_button(list, kept) end)
        |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)
        |> within("#expense-conflicts", fn panel ->
          click_button(panel, "Make this the value")
        end)

      session
      |> refute_has("#expense-editor button", text: "Conflicts")
      |> refute_has("#conflict-bell")
      |> assert_has("#expenses", text: dropped)
      |> refute_has("#expenses", text: kept)
    end

    test "Dismiss conflict clears just that one and leaves the others", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})
      {:ok, lunch} = Tracking.add_expense(book.id, %{description: "Lunch", cost: "9.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      kept =
        seed_two_conflicts(
          tmp_dir,
          book.id,
          {coffee.id, "Espresso", "Latte"},
          {lunch.id, "Dinner", "Supper"}
        )

      session =
        session
        |> assert_has("#conflict-bell", text: "2", timeout: 100)
        |> within("#expenses", fn list -> click_button(list, kept[coffee.id]) end)
        |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)
        |> within("#expense-conflicts", fn panel -> click_button(panel, "Dismiss conflict") end)

      # Coffee's tab is gone, but the lunch conflict still lights the badge.
      session
      |> refute_has("#expense-editor button", text: "Conflicts")
      |> assert_has("#conflict-bell", text: "1")
    end

    test "renders every alternative for a three-or-more-edit conflict, and overrides the chosen one",
         ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")

      conflict =
        seed_three_way_conflict(tmp_dir, book.id, coffee.id, ["Espresso", "Latte", "Mocha"])

      # Automerge picks the winner by op id, so which value is kept is not fixed; target the
      # first alternative by its rendered index rather than assume any particular winner.
      [first_alternative | _] = conflict.alternatives

      session =
        session
        |> assert_has("#conflict-bell", timeout: 100)
        |> within("#expenses", fn list -> click_button(list, conflict.kept.value) end)
        |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)

      # All three concurrent values render — the kept one plus both alternatives — proving the
      # tab is not hardwired to a single pair.
      session
      |> assert_has("#expense-conflicts", text: "Espresso")
      |> assert_has("#expense-conflicts", text: "Latte")
      |> assert_has("#expense-conflicts", text: "Mocha")
      |> assert_has("#expense-conflicts button", text: "Make this the value", count: 2)

      # Overriding the first alternative's row makes exactly that value win going forward.
      session
      |> within("#expense-conflicts-description-0", fn row ->
        click_button(row, "Make this the value")
      end)
      |> refute_has("#conflict-bell")
      |> assert_has("#expenses", text: first_alternative.value)
    end

    test "copy names LocalCents and never the sync internals", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})

      session = visit(conn, ~p"/books/#{book.id}")
      kept = seed_scalar_conflict(tmp_dir, book.id, coffee.id, "Espresso", "Latte")

      session
      |> assert_has("#conflict-bell", timeout: 100)
      |> within("#expenses", fn list -> click_button(list, kept) end)
      |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)
      |> assert_has("#expense-conflicts", text: "LocalCents")
      |> refute_has("#expense-conflicts", text: "Automerge")
      |> refute_has("#expense-conflicts", text: "CRDT")
    end

    # A Category conflict arrives as the stored field `category_id`; the copy must name the
    # Category, not leak the column name as "Category_id" (#268).
    test "a Category conflict labels the field Category, not category_id", ~M{conn, tmp_dir} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      {:ok, coffee} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.00"})
      {:ok, groceries} = Tracking.add_category(book.id, %{name: "Groceries"})
      {:ok, transit} = Tracking.add_category(book.id, %{name: "Transit"})

      session = visit(conn, ~p"/books/#{book.id}")
      seed_category_conflict(tmp_dir, book.id, coffee.id, groceries.id, transit.id)

      session = assert_has(session, "#conflict-bell", timeout: 100)

      # The Synced changes popup names the field for the reader, not its stored column.
      session =
        session
        |> click_button("Synced changes")
        |> assert_has("#synced-changes-popup", text: "Synced edits to Category")
        |> refute_has("#synced-changes-popup", text: "Category_id")

      # The editor's Conflicts tab heads the same conflict with the same label.
      session
      |> within("#expenses", fn list -> click_button(list, "Coffee") end)
      |> within("#expense-editor", fn editor -> click_button(editor, "Conflicts") end)
      |> assert_has("#expense-conflicts", text: "Category")
      |> refute_has("#expense-conflicts", text: "Category_id")
    end
  end

  # Forks a second peer, retitles `expense_id` to a different value on each side across
  # the suspended link, and reconciles — the scalar conflict LocalCents auto-resolves.
  # Returns the value LocalCents kept, so a caller can open that Expense's row by text.
  defp seed_scalar_conflict(tmp_dir, book_id, expense_id, this_value, other_value) do
    peer_b = fork_peer(tmp_dir, book_id)
    {:ok, _} = Tracking.edit_expense(book_id, expense_id, %{description: this_value})
    {:ok, _} = Tracking.edit_expense(peer_b, expense_id, %{description: other_value})
    reconcile(book_id, peer_b)

    %{field_conflicts: conflicts} = Tracking.conflict_summary(book_id)
    conflict = Enum.find(conflicts, &(&1.expense_id == expense_id))
    conflict.kept.value
  end

  # Files `expense_id` under a different Category on each of two peers across a suspended
  # link, then reconciles — producing the auto-resolved `category_id` scalar conflict whose
  # label must read "Category", not the stored column name.
  defp seed_category_conflict(tmp_dir, book_id, expense_id, this_category, other_category) do
    peer_b = fork_peer(tmp_dir, book_id)
    {:ok, _} = Tracking.assign_category(book_id, expense_id, this_category)
    {:ok, _} = Tracking.assign_category(peer_b, expense_id, other_category)
    reconcile(book_id, peer_b)
  end

  # Two expenses diverge on one peer pair, then a single reconcile — so both scalar conflicts
  # coexist. They must surface in the same merge: a later per-expense edit reconciles the whole
  # winner-only state and would collapse the earlier conflict's register. Returns a `%{id => kept}`
  # map so a caller can open either conflicted row by text.
  defp seed_two_conflicts(tmp_dir, book_id, {id_a, a_this, a_other}, {id_b, b_this, b_other}) do
    peer_b = fork_peer(tmp_dir, book_id)
    {:ok, _} = Tracking.edit_expense(book_id, id_a, %{description: a_this})
    {:ok, _} = Tracking.edit_expense(book_id, id_b, %{description: b_this})
    {:ok, _} = Tracking.edit_expense(peer_b, id_a, %{description: a_other})
    {:ok, _} = Tracking.edit_expense(peer_b, id_b, %{description: b_other})
    reconcile(book_id, peer_b)

    %{field_conflicts: conflicts} = Tracking.conflict_summary(book_id)
    Map.new(conflicts, &{&1.expense_id, &1.kept.value})
  end

  # Edits each expense here while a forked peer deletes it across the suspended link, then
  # reconciles — so each surfaces as an edit-vs-delete conflict whose dropped edit the popup's
  # "Needs your decision" group offers to restore or keep deleted. Takes one `{id, edit}` pair
  # or a list of them.
  defp seed_edit_delete_conflict(tmp_dir, book_id, expense_id, edit) when is_binary(expense_id) do
    seed_edit_delete_conflict(tmp_dir, book_id, [{expense_id, edit}])
  end

  defp seed_edit_delete_conflict(tmp_dir, book_id, pairs) when is_list(pairs) do
    peer_b = fork_peer(tmp_dir, book_id)

    for {expense_id, edit} <- pairs do
      {:ok, _} = Tracking.edit_expense(book_id, expense_id, %{description: edit})
      :ok = Tracking.delete_expense(peer_b, expense_id)
    end

    reconcile(book_id, peer_b)
  end

  # Three peers retitle the same expense's description while apart, so the reconciled register
  # holds three concurrent values — one kept plus two alternatives. Returns the field conflict.
  defp seed_three_way_conflict(tmp_dir, book_id, expense_id, [v0, v1, v2]) do
    peer_1 = fork_peer(tmp_dir, book_id)
    peer_2 = fork_peer(tmp_dir, book_id)
    {:ok, _} = Tracking.edit_expense(book_id, expense_id, %{description: v0})
    {:ok, _} = Tracking.edit_expense(peer_1, expense_id, %{description: v1})
    {:ok, _} = Tracking.edit_expense(peer_2, expense_id, %{description: v2})
    reconcile(book_id, peer_1)
    reconcile(book_id, peer_2)

    %{field_conflicts: [conflict]} = Tracking.conflict_summary(book_id)
    conflict
  end
end
