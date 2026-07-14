defmodule LocalCents.Tracking.BookDocumentTest do
  # The functional core is pure data in / data out — no process, no NIF — so these
  # run async and prove the domain rules directly (see ADR 0014). Integration with
  # persistence and broadcasting is covered in `LocalCents.TrackingTest`.
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.BookDocument
  alias LocalCents.Tracking.Category
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
    test "round-trips name, categories, and expenses, converting date/cost and category_id" do
      raw = %{
        name: "Family",
        categories: [%{id: "c1", name: "Groceries"}],
        expenses: [
          %{id: "a", date: "2026-06-02", description: "Coffee", cost: "12.34", category_id: "c1"},
          %{id: "b", date: "2026-06-03", description: "Gift", cost: nil, category_id: nil}
        ]
      }

      document = BookDocument.from_raw(raw)

      assert [%Category{id: "c1", name: "Groceries"}] = BookDocument.categories(document)

      assert [
               %Expense{
                 id: "a",
                 date: ~D[2026-06-02],
                 description: "Coffee",
                 cost: coffee_cost,
                 category_id: "c1"
               },
               %Expense{
                 id: "b",
                 date: ~D[2026-06-03],
                 description: "Gift",
                 cost: nil,
                 category_id: nil
               }
             ] = BookDocument.expenses(document)

      assert Decimal.equal?(coffee_cost, Decimal.new("12.34"))
      assert BookDocument.to_raw(document) == raw
    end
  end

  describe "add_category/3" do
    @cat_id "22222222-2222-4222-8222-222222222222"

    test "appends a validated Category and returns it" do
      assert {:ok, document, category} =
               BookDocument.add_category(empty_document(), %{name: "Groceries"}, @cat_id)

      assert %Category{id: @cat_id, name: "Groceries"} = category
      assert BookDocument.categories(document) == [category]
    end

    test "the name is trimmed" do
      assert {:ok, _document, %Category{name: "Groceries"}} =
               BookDocument.add_category(empty_document(), %{name: "  Groceries  "}, @cat_id)
    end

    test "a blank name is rejected" do
      assert {:error, changeset} =
               BookDocument.add_category(empty_document(), %{name: "   "}, @cat_id)

      assert "can't be blank" in errors_on(changeset).name
    end

    test "appends in insertion order" do
      {:ok, document, _} = BookDocument.add_category(empty_document(), %{name: "First"}, "a")
      {:ok, document, _} = BookDocument.add_category(document, %{name: "Second"}, "b")

      assert ["First", "Second"] = Enum.map(BookDocument.categories(document), & &1.name)
    end
  end

  describe "rename_category/3" do
    setup do
      {:ok, document, _} = BookDocument.add_category(empty_document(), %{name: "Groceries"}, "c1")
      %{document: document}
    end

    test "changes only the name, preserving the id", %{document: document} do
      assert {:ok, document, category} =
               BookDocument.rename_category(document, "c1", %{name: "Food"})

      assert %Category{id: "c1", name: "Food"} = category
      assert BookDocument.categories(document) == [category]
    end

    test "does not touch the category_id of filed expenses", %{document: document} do
      {:ok, document, _} =
        BookDocument.add_expense(document, %{description: "Milk"}, "e1", @today)

      {:ok, document, _} = BookDocument.assign_category(document, "e1", "c1")
      {:ok, document, _} = BookDocument.rename_category(document, "c1", %{name: "Food"})

      assert [%Expense{category_id: "c1"}] = BookDocument.expenses(document)
    end

    test "an unknown id returns :not_found", %{document: document} do
      assert {:error, :not_found} =
               BookDocument.rename_category(document, "nope", %{name: "Food"})
    end

    test "a blank name is rejected", %{document: document} do
      assert {:error, changeset} = BookDocument.rename_category(document, "c1", %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "delete_category/2" do
    setup do
      {:ok, document, _} = BookDocument.add_category(empty_document(), %{name: "Groceries"}, "c1")
      %{document: document}
    end

    test "removes the category", %{document: document} do
      assert {:ok, document} = BookDocument.delete_category(document, "c1")
      assert BookDocument.categories(document) == []
    end

    test "un-files expenses filed under it, leaving others untouched", %{document: document} do
      {:ok, document, _} = BookDocument.add_category(document, %{name: "Transit"}, "c2")

      {:ok, document, _} =
        BookDocument.add_expense(document, %{description: "Milk"}, "e1", @today)

      {:ok, document, _} = BookDocument.add_expense(document, %{description: "Bus"}, "e2", @today)
      {:ok, document, _} = BookDocument.add_expense(document, %{description: "Gum"}, "e3", @today)
      {:ok, document, _} = BookDocument.assign_category(document, "e1", "c1")
      {:ok, document, _} = BookDocument.assign_category(document, "e2", "c2")

      assert {:ok, document} = BookDocument.delete_category(document, "c1")

      by_id = Map.new(BookDocument.expenses(document), &{&1.id, &1.category_id})
      assert by_id == %{"e1" => nil, "e2" => "c2", "e3" => nil}
    end

    test "an unknown id returns :not_found", %{document: document} do
      assert {:error, :not_found} = BookDocument.delete_category(document, "nope")
    end
  end

  describe "assign_category/3 and unassign_category/2" do
    setup do
      {:ok, document, _} = BookDocument.add_category(empty_document(), %{name: "Groceries"}, "c1")

      {:ok, document, _} =
        BookDocument.add_expense(document, %{description: "Milk"}, "e1", @today)

      %{document: document}
    end

    test "files an expense under a category", %{document: document} do
      assert {:ok, document, %Expense{id: "e1", category_id: "c1"}} =
               BookDocument.assign_category(document, "e1", "c1")

      assert [%Expense{category_id: "c1"}] = BookDocument.expenses(document)
    end

    test "replaces a prior category (at most one)", %{document: document} do
      {:ok, document, _} = BookDocument.add_category(document, %{name: "Transit"}, "c2")
      {:ok, document, _} = BookDocument.assign_category(document, "e1", "c1")

      assert {:ok, _document, %Expense{category_id: "c2"}} =
               BookDocument.assign_category(document, "e1", "c2")
    end

    test "an unknown expense returns :expense_not_found", %{document: document} do
      assert {:error, :expense_not_found} =
               BookDocument.assign_category(document, "nope", "c1")
    end

    test "an unknown category returns :category_not_found", %{document: document} do
      assert {:error, :category_not_found} =
               BookDocument.assign_category(document, "e1", "nope")
    end

    test "unassign nulls the category_id", %{document: document} do
      {:ok, document, _} = BookDocument.assign_category(document, "e1", "c1")

      assert {:ok, document, %Expense{category_id: nil}} =
               BookDocument.unassign_category(document, "e1")

      assert [%Expense{category_id: nil}] = BookDocument.expenses(document)
    end

    test "unassign on an unknown expense returns :expense_not_found", %{document: document} do
      assert {:error, :expense_not_found} = BookDocument.unassign_category(document, "nope")
    end

    test "an edit of the expense preserves its category_id", %{document: document} do
      {:ok, document, _} = BookDocument.assign_category(document, "e1", "c1")

      assert {:ok, _document, %Expense{category_id: "c1", description: "Whole milk"}} =
               BookDocument.edit_expense(document, "e1", %{description: "Whole milk"}, @today)
    end
  end
end
