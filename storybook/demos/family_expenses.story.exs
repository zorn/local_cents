defmodule Storybook.Demos.FamilyExpenses do
  use LocalCentsWeb.Storybook.Story, :example

  def doc,
    do:
      "The Family Expenses book window — quick-add bar, expense list, and slide-in editor, composed entirely from Bond components. This demo tracks what `LocalCentsWeb.BookLive` actually renders; click a row to open the editor, then Delete to see the confirmation modal."

  @categories [
    %{id: 1, name: "Groceries"},
    %{id: 2, name: "Dining"},
    %{id: 3, name: "Kids"},
    %{id: 4, name: "Home"}
  ]

  @expenses [
    %{
      id: 1,
      date: "06/01/2026",
      description: "Whole Foods grocery run",
      category_id: 1,
      amount: "$127.43"
    },
    %{
      id: 2,
      date: "05/30/2026",
      description: "Dinner at Olive Garden",
      category_id: 2,
      amount: "$67.50"
    },
    %{
      id: 3,
      date: "05/28/2026",
      description: "Summer soccer registration",
      category_id: 3,
      amount: "$67.50"
    },
    %{
      id: 4,
      date: "05/25/2026",
      description: "Target run — school supplies",
      category_id: 3,
      amount: "$43.18"
    },
    %{
      id: 5,
      date: "05/22/2026",
      description: "Trader Joe's",
      category_id: 1,
      amount: "$89.76"
    },
    %{
      id: 6,
      date: "05/20/2026",
      description: "Chipotle lunch",
      category_id: 2,
      amount: "$22.14"
    },
    # Filing is optional (ADR 0018) — a blank category reads as Uncategorized, so
    # the list keeps one to show the row without a category pill.
    %{
      id: 7,
      date: "05/18/2026",
      description: "Netflix subscription",
      category_id: nil,
      amount: "$22.99"
    },
    %{
      id: 8,
      date: "05/15/2026",
      description: "Baseball cleats",
      category_id: 3,
      amount: "$54.99"
    },
    %{
      id: 9,
      date: "05/12/2026",
      description: "New shower head",
      category_id: 4,
      amount: "$38.55"
    },
    %{
      id: 10,
      date: "05/10/2026",
      description: "Pizza night",
      category_id: 2,
      amount: "$38.00"
    }
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       expenses: @expenses,
       categories: @categories,
       editing: nil,
       confirming_delete: false
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("edit_expense", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, :editing, Enum.find(socket.assigns.expenses, &(&1.id == id)))}
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply, assign(socket, editing: nil, confirming_delete: false)}
  end

  def handle_event("request_delete", _params, socket) do
    # Delete is only offered inside the open editor, so a request arriving with no
    # expense in hand can only come from a stale client. Staying closed keeps the
    # modal's `@editing.description` read total.
    {:noreply, assign(socket, :confirming_delete, socket.assigns.editing != nil)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirming_delete, false)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="font-sans">
      <p class="text-xs text-surface-500 mb-2">
        Drag the bottom-right corner to resize the window and watch the elements reflow.
      </p>
      <div class="resize-x overflow-hidden min-w-[320px] max-w-full w-[576px] p-6">
        <Bond.desktop_window title="Family Expenses">
          <%!-- `relative` scopes the editor's `absolute inset-0` to the content area
          below the title bar, matching how BookLive frames its own panel. --%>
          <div class="relative overflow-hidden">
            <%!-- Quick add sits at the top so a long list never scrolls it out of reach. --%>
            <div class="pt-4 pb-3">
              <Bond.input_bar>
                <:leading_content>
                  <label for="demo-quick-add-input" class="sr-only">Quick add expense</label>
                  <Bond.input
                    id="demo-quick-add-input"
                    placeholder="coffee 4.75"
                    class="flex-1"
                    autocomplete="off"
                  />
                </:leading_content>
                <:trailing_content>
                  <Bond.button>New Expense</Bond.button>
                </:trailing_content>
              </Bond.input_bar>
            </div>

            <Bond.list_view max_height="420px">
              <Bond.expense_cell
                :for={expense <- @expenses}
                id={"demo-expense-#{expense.id}"}
                date_display={expense.date}
                description={expense.description}
                amount_display={expense.amount}
                category={category_name(@categories, expense.category_id)}
                phx-click="edit_expense"
                phx-value-id={expense.id}
              />
            </Bond.list_view>

            <div class="flex items-center gap-2 p-4">
              <Bond.button variant={:outline}>Categories</Bond.button>
              <Bond.button variant={:outline}>Report</Bond.button>
            </div>

            <Bond.side_panel
              :if={@editing}
              id="demo-expense-editor"
              title="Edit Expense"
              on_close="close_editor"
            >
              <form class="space-y-3">
                <Bond.input
                  id="demo-editor-date"
                  label="Date"
                  type="date"
                  variant="frosted"
                  class="w-full"
                  value={to_date_input(@editing.date)}
                />
                <Bond.input
                  id="demo-editor-description"
                  label="Description"
                  variant="frosted"
                  class="w-full"
                  value={@editing.description}
                />
                <Bond.input
                  id="demo-editor-cost"
                  label="Cost"
                  variant="frosted"
                  class="w-full"
                  placeholder="0.00"
                  value={@editing.amount}
                />
                <%!-- Filing is a plain form field (ADR 0018): the blank option is
                Uncategorized, which is why include_blank is left at its default. --%>
                <Bond.select
                  id="demo-editor-category"
                  label="Category"
                  variant="frosted"
                  class="w-full"
                  options={category_options(@categories)}
                  value={@editing.category_id}
                />
              </form>
              <:footer>
                <Bond.button type="button" variant={:destructive} phx-click="request_delete">
                  Delete
                </Bond.button>
                <Bond.button type="button">Save</Bond.button>
              </:footer>
            </Bond.side_panel>
          </div>
        </Bond.desktop_window>
      </div>

      <Bond.modal
        :if={@confirming_delete}
        id="demo-delete-expense-modal"
        title="Delete Expense"
        on_cancel="cancel_delete"
      >
        <p class="text-sm text-surface-700">
          Delete <span class="font-semibold">{@editing.description}</span>? This permanently
          removes the expense and cannot be undone.
        </p>
        <:actions>
          <Bond.button type="button" variant={:outline} phx-click="cancel_delete">Cancel</Bond.button>
          <Bond.button type="button" variant={:destructive} phx-click="close_editor">
            Delete
          </Bond.button>
        </:actions>
      </Bond.modal>
    </div>
    """
  end

  defp category_name(_categories, nil), do: nil

  defp category_name(categories, id) do
    Enum.find_value(categories, fn category -> category.id == id && category.name end)
  end

  defp category_options(categories), do: Enum.map(categories, &{&1.name, &1.id})

  defp to_date_input(date) do
    case String.split(date, "/") do
      [m, d, y] -> "#{y}-#{m}-#{d}"
      _ -> date
    end
  end
end
