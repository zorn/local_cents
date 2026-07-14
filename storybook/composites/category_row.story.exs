defmodule Storybook.Composites.CategoryRow do
  use LocalCentsWeb.Storybook.Story, :component

  alias LocalCents.Tracking.Category

  def function, do: &Bond.Composites.CategoryRow.category_row/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :display_many,
        description: "Display row for a category with several expenses filed under it.",
        attributes: %{
          id: "category-row-groceries",
          category_id: "cat-1",
          name: "Groceries",
          count: 12,
          on_edit: "edit_category",
          on_delete: "request_delete"
        }
      },
      %Variation{
        id: :display_one,
        description: "Display row whose count is singular.",
        attributes: %{
          id: "category-row-rent",
          category_id: "cat-2",
          name: "Rent",
          count: 1,
          on_edit: "edit_category",
          on_delete: "request_delete"
        }
      },
      %Variation{
        id: :display_zero,
        description: "Display row for a category with no expenses yet.",
        attributes: %{
          id: "category-row-travel",
          category_id: "cat-3",
          name: "Travel",
          count: 0,
          on_edit: "edit_category",
          on_delete: "request_delete"
        }
      },
      %Variation{
        id: :edit_blank,
        description: "Edit mode with an empty field — the add-a-category row.",
        attributes: %{
          id: "category-row-new",
          editing: true,
          input_id: "category-name-new",
          form: name_form(%Category{}, %{}),
          submit_label: "Create",
          on_save: "save_category",
          on_cancel: "cancel_edit"
        }
      },
      %Variation{
        id: :edit_prefilled,
        description: "Edit mode prefilled with an existing name — the rename row.",
        attributes: %{
          id: "category-row-edit-cat-1",
          editing: true,
          input_id: "category-name-cat-1",
          form: name_form(%Category{id: "cat-1", name: "Groceries"}, %{}),
          on_save: "save_category",
          on_cancel: "cancel_edit"
        }
      },
      %Variation{
        id: :edit_invalid,
        description: "Edit mode after submitting a blank name — the validation error shows.",
        attributes: %{
          id: "category-row-invalid",
          editing: true,
          input_id: "category-name-invalid",
          form: name_form(%Category{}, %{"name" => ""}),
          on_save: "save_category",
          on_cancel: "cancel_edit"
        }
      }
    ]
  end

  # A form over the Category name field, mirroring how BookCategoriesLive builds it.
  defp name_form(category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Phoenix.Component.to_form()
  end
end
