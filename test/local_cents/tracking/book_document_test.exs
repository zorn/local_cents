defmodule LocalCents.Tracking.BookDocumentTest do
  # The functional core is pure data in / data out — no process, no NIF — so these
  # run async and prove the domain rules directly (see ADR 0014). Integration with
  # persistence and broadcasting is covered in `LocalCents.TrackingTest`.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Expense

  @today ~D[2026-07-11]
  @id "11111111-1111-4111-8111-111111111111"

  defp empty_document(name \\ "Family"), do: %BookDocument{name: name, expenses: []}

  # Mirrors the `errors_on/1` helper common in Phoenix projects: expands a
  # changeset's errors into `%{field => [interpolated messages]}` so tests can
  # assert on the actual message, not just which field failed.
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r/%\{(\w+)\}/, message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "add_expense/4" do
    test "appends a validated Expense and returns it" do
      assert {:ok, document, expense} =
               BookDocument.add_expense(
                 empty_document(),
                 %{date: ~D[2026-06-02], description: "Coffee", cost: "12.34"},
                 @id,
                 @today
               )

      assert %Expense{id: @id, date: ~D[2026-06-02], description: "Coffee"} = expense
      assert Decimal.equal?(expense.cost, Decimal.new("12.34"))
      assert BookDocument.expenses(document) == [expense]
    end

    test "a blank date defaults to the injected today" do
      assert {:ok, _document, %Expense{date: @today}} =
               BookDocument.add_expense(empty_document(), %{description: "Coffee"}, @id, @today)
    end

    test "an absent cost is nil, not zero" do
      assert {:ok, _document, %Expense{cost: nil}} =
               BookDocument.add_expense(empty_document(), %{description: "Coffee"}, @id, @today)
    end

    test "a genuine zero cost is allowed and distinct from nil" do
      assert {:ok, _document, %Expense{cost: cost}} =
               BookDocument.add_expense(
                 empty_document(),
                 %{description: "Free sample", cost: "0"},
                 @id,
                 @today
               )

      assert Decimal.equal?(cost, Decimal.new("0"))
    end

    test "a negative cost is rejected" do
      assert {:error, changeset} =
               BookDocument.add_expense(
                 empty_document(),
                 %{description: "Refund", cost: "-5"},
                 @id,
                 @today
               )

      assert "must be zero or greater" in errors_on(changeset).cost
    end

    test "a missing description is rejected" do
      assert {:error, changeset} =
               BookDocument.add_expense(empty_document(), %{cost: "5"}, @id, @today)

      assert "can't be blank" in errors_on(changeset).description
    end

    test "a whitespace-only description is rejected" do
      assert {:error, changeset} =
               BookDocument.add_expense(empty_document(), %{description: "   "}, @id, @today)

      assert "can't be blank" in errors_on(changeset).description
    end

    test "the description is trimmed" do
      assert {:ok, _document, %Expense{description: "Coffee"}} =
               BookDocument.add_expense(
                 empty_document(),
                 %{description: "  Coffee  "},
                 @id,
                 @today
               )
    end

    test "appends in insertion order" do
      {:ok, document, _} =
        BookDocument.add_expense(empty_document(), %{description: "First"}, "a", @today)

      {:ok, document, _} =
        BookDocument.add_expense(document, %{description: "Second"}, "b", @today)

      assert ["First", "Second"] = Enum.map(BookDocument.expenses(document), & &1.description)
    end
  end

  describe "edit_expense/4" do
    setup do
      {:ok, document, _} =
        BookDocument.add_expense(
          empty_document(),
          %{date: ~D[2026-06-02], description: "Coffee", cost: "5.00"},
          @id,
          @today
        )

      %{document: document}
    end

    test "replaces every editable field, preserving the id", %{document: document} do
      assert {:ok, document, expense} =
               BookDocument.edit_expense(
                 document,
                 @id,
                 %{date: ~D[2026-06-03], description: "Latte", cost: "6.50"},
                 @today
               )

      assert %Expense{id: @id, date: ~D[2026-06-03], description: "Latte"} = expense
      assert Decimal.equal?(expense.cost, Decimal.new("6.50"))
      assert BookDocument.expenses(document) == [expense]
    end

    test "clearing the cost sets it back to nil", %{document: document} do
      assert {:ok, _document, %Expense{cost: nil}} =
               BookDocument.edit_expense(
                 document,
                 @id,
                 %{description: "Coffee", cost: ""},
                 @today
               )
    end

    test "an unknown id returns :not_found", %{document: document} do
      assert {:error, :not_found} =
               BookDocument.edit_expense(document, "nope", %{description: "X"}, @today)
    end

    test "invalid attrs return a changeset", %{document: document} do
      assert {:error, changeset} =
               BookDocument.edit_expense(document, @id, %{description: ""}, @today)

      assert "can't be blank" in errors_on(changeset).description
    end
  end

  describe "delete_expense/2" do
    setup do
      {:ok, document, _} =
        BookDocument.add_expense(empty_document(), %{description: "Coffee"}, @id, @today)

      %{document: document}
    end

    test "removes the expense", %{document: document} do
      assert {:ok, document} = BookDocument.delete_expense(document, @id)
      assert BookDocument.expenses(document) == []
    end

    test "an unknown id returns :not_found", %{document: document} do
      assert {:error, :not_found} = BookDocument.delete_expense(document, "nope")
    end
  end

  describe "rename/2" do
    test "changes the name" do
      assert {:ok, %BookDocument{name: "Household"}} =
               BookDocument.rename(empty_document("Family"), "Household")
    end
  end

  describe "from_raw/1 and to_raw/1" do
    test "round-trips name and expenses, converting date and cost to and from raw form" do
      raw = %{
        name: "Family",
        expenses: [
          %{id: "a", date: "2026-06-02", description: "Coffee", cost: "12.34"},
          %{id: "b", date: "2026-06-03", description: "Gift", cost: nil}
        ]
      }

      document = BookDocument.from_raw(raw)

      assert [
               %Expense{id: "a", date: ~D[2026-06-02], description: "Coffee", cost: coffee_cost},
               %Expense{id: "b", date: ~D[2026-06-03], description: "Gift", cost: nil}
             ] = BookDocument.expenses(document)

      assert Decimal.equal?(coffee_cost, Decimal.new("12.34"))
      assert BookDocument.to_raw(document) == raw
    end
  end
end
