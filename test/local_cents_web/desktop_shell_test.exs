defmodule LocalCentsWeb.DesktopShellTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.Book
  alias LocalCentsWeb.DesktopShell

  describe "open_book_command/1" do
    test "encodes an open-window command tagged with the Book's id" do
      book = %Book{id: "abc-123", name: "Family Expenses"}

      assert %{
               "action" => "open-window",
               "label" => "book-abc-123",
               "path" => "/books/abc-123",
               "title" => "Family Expenses"
             } = Jason.decode!(DesktopShell.open_book_command(book))
    end

    test "the label and path both carry the id verbatim so Rust can key the window" do
      book = %Book{id: "0192f3c1-dead-beef", name: "Side Hustle"}

      decoded = Jason.decode!(DesktopShell.open_book_command(book))

      assert decoded["label"] == "book-0192f3c1-dead-beef"
      assert decoded["path"] == "/books/0192f3c1-dead-beef"
    end
  end

  describe "close_book_command/1" do
    test "encodes a close-window command tagged with the Book's id" do
      book = %Book{id: "abc-123", name: "Family Expenses"}

      assert %{"action" => "close-window", "label" => "book-abc-123"} =
               Jason.decode!(DesktopShell.close_book_command(book))
    end

    test "carries only the action and label — Rust needs no path or title to close" do
      book = %Book{id: "abc-123", name: "Family Expenses"}

      keys = book |> DesktopShell.close_book_command() |> Jason.decode!() |> Map.keys()

      assert Enum.sort(keys) == ["action", "label"]
    end
  end

  describe "set_title_command/1" do
    test "encodes a set-title command with the window label and the Book's name" do
      book = %Book{id: "abc-123", name: "Household"}

      assert %{"action" => "set-title", "label" => "book-abc-123", "title" => "Household"} =
               Jason.decode!(DesktopShell.set_title_command(book))
    end
  end
end
