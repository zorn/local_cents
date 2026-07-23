defmodule LocalCentsWeb.BookReportLiveTest do
  # Not async: opening Books uses the global :books_dir env.
  use LocalCentsWeb.FeatureCase, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking

  setup :with_temp_books_dir

  # Fixed dates keep the fixtures deterministic; tests visit with `?range=all` so the
  # whole-Book span is used regardless of the wall clock.
  defp add_expense(book_id, attrs), do: {:ok, _} = Tracking.add_expense(book_id, attrs)

  describe "navigation" do
    test "reaches the report page from the document window and back", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}")
      |> click_button("Report")
      |> assert_path(~p"/books/#{book.id}/report")
      |> assert_has("h1", text: "Report")
      |> click_link("Expenses")
      |> assert_path(~p"/books/#{book.id}")
      |> assert_has("h1", text: "Family Expenses")
    end

    test "an unknown book redirects to the library", ~M{conn} do
      conn
      |> visit(~p"/books/does-not-exist/report")
      |> assert_path(~p"/library")
      |> assert_has("h1", text: "Library")
    end
  end

  describe "the matrix" do
    test "renders a known grand total", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      add_expense(book.id, %{date: ~D[2026-01-10], description: "Milk", cost: "10.00"})
      add_expense(book.id, %{date: ~D[2026-02-10], description: "Bread", cost: "20.00"})

      conn
      |> visit(~p"/books/#{book.id}/report?range=all")
      |> assert_has("td", text: "$30.00", timeout: 500)
    end

    test "shows an empty state when the book has no expenses", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/report?range=all")
      |> assert_has("p", text: "No expenses yet", timeout: 500)
    end

    test "the empty state for a trailing range reads range-aware, not book-empty", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")

      conn
      |> visit(~p"/books/#{book.id}/report?range=3")
      |> assert_has("p", text: "No spending in this range", timeout: 500)
    end
  end

  describe "refresh on demand" do
    test "a change elsewhere shows a stale banner; Refresh recomputes", ~M{conn} do
      {:ok, book} = Tracking.create_book("Family Expenses")
      add_expense(book.id, %{date: ~D[2026-01-10], description: "Milk", cost: "10.00"})

      session =
        conn
        |> visit(~p"/books/#{book.id}/report?range=all")
        |> assert_has("td", text: "$10.00", timeout: 500)

      # A change in another view broadcasts {:book_updated}; the report goes stale
      # rather than recomputing under the reader.
      add_expense(book.id, %{date: ~D[2026-01-11], description: "Eggs", cost: "5.00"})

      session
      |> assert_has("span", text: "This report may be out of date.", timeout: 500)
      |> click_button("Refresh")
      |> assert_has("td", text: "$15.00", timeout: 500)
      |> refute_has("span", text: "This report may be out of date.")
    end
  end
end
