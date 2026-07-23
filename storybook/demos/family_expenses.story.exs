defmodule Storybook.Demos.FamilyExpenses do
  use LocalCentsWeb.Storybook.Story, :example

  def doc,
    do:
      "The Family Expenses document window — a chart, entry bar, expense table, and slide-in edit panel, composed entirely from Bond components. Click a row to open the edit panel."

  @available_tags [
    %{label: "kids"},
    %{label: "some-long-tag-name"},
    %{label: "food"},
    %{label: "sports"},
    %{label: "groceries"},
    %{label: "dining"}
  ]

  @expenses [
    %{
      id: 1,
      date: "06/01/2026",
      description: "Whole Foods grocery run",
      tags: ["groceries", "food"],
      amount: "$127.43"
    },
    %{
      id: 2,
      date: "05/30/2026",
      description: "Dinner at Olive Garden",
      tags: ["dining"],
      amount: "$67.50"
    },
    %{
      id: 3,
      date: "05/28/2026",
      description: "Summer soccer registration",
      tags: ["kids", "sports"],
      amount: "$67.50"
    },
    %{
      id: 4,
      date: "05/25/2026",
      description: "Target run — school supplies",
      tags: ["kids"],
      amount: "$43.18"
    },
    %{
      id: 5,
      date: "05/22/2026",
      description: "Trader Joe's",
      tags: ["groceries", "food"],
      amount: "$89.76"
    },
    %{
      id: 6,
      date: "05/20/2026",
      description: "Chipotle lunch",
      tags: ["dining", "food"],
      amount: "$22.14"
    },
    %{
      id: 7,
      date: "05/18/2026",
      description: "Netflix subscription",
      tags: [],
      amount: "$22.99"
    },
    %{
      id: 8,
      date: "05/15/2026",
      description: "Baseball cleats",
      tags: ["kids", "sports"],
      amount: "$54.99"
    },
    %{
      id: 9,
      date: "05/12/2026",
      description: "Costco run",
      tags: ["groceries"],
      amount: "$213.55"
    },
    %{
      id: 10,
      date: "05/10/2026",
      description: "Pizza night",
      tags: ["dining"],
      amount: "$38.00"
    }
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       expenses: @expenses,
       available_tags: @available_tags,
       selected_expense: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("select_expense", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = Enum.find(socket.assigns.expenses, &(&1.id == id))
    {:noreply, assign(socket, :selected_expense, selected)}
  end

  def handle_event("close_expense", _params, socket) do
    {:noreply, assign(socket, :selected_expense, nil)}
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
          <%!-- Content area (edit panel is relative to this, not the title bar) --%>
          <div class="relative overflow-hidden">
            <.grid_chart_placeholder />
            <%!-- New Expense row --%>
            <Bond.input_bar>
              <:leading_content>
                <Bond.input
                  id="demo-new-expense-input"
                  placeholder="coffee 4.75"
                  class="flex-1"
                />
              </:leading_content>
              <:trailing_content>
                <Bond.button id="demo-new-expense-create-btn">
                  New Expense
                </Bond.button>
              </:trailing_content>
            </Bond.input_bar>
            <%!-- Expense table --%>
            <Bond.list_view max_height="420px">
              <:header>
                <Bond.list_controls>
                  <:leading_content>
                    <Bond.input
                      type="search"
                      id="demo-expense-search-input"
                      placeholder="search..."
                      class="flex-1"
                    />
                  </:leading_content>
                  <:trailing_content>
                    <Bond.action_chip label="Tags" />
                    <Bond.action_chip label="↕ Newest" />
                  </:trailing_content>
                </Bond.list_controls>
              </:header>
              <Bond.expense_cell
                :for={expense <- @expenses}
                id={"demo-expense-row-#{expense.id}"}
                date_display={expense.date}
                description={expense.description}
                amount_display={expense.amount}
                category={demo_category(expense.tags)}
                phx-click="select_expense"
                phx-value-id={expense.id}
              />
            </Bond.list_view>
            <%!-- Edit panel --%>
            <%= if @selected_expense do %>
              <Bond.side_panel
                id="demo-expense-edit-panel"
                title="Edit Expense"
                on_close="close_expense"
              >
                <div class="space-y-3">
                  <Bond.input
                    label="Date"
                    type="date"
                    variant="frosted"
                    class="w-full"
                    value={to_date_input(@selected_expense.date)}
                  />
                  <Bond.input
                    label="Description"
                    variant="frosted"
                    class="w-full"
                    value={@selected_expense.description}
                  />
                  <Bond.input
                    label="Cost"
                    variant="frosted"
                    class="w-full"
                    value={@selected_expense.amount}
                  />
                  <div>
                    <label class="text-xs font-semibold text-primary-400 uppercase tracking-wide block mb-2 px-1">
                      Tags
                    </label>
                    <div class="space-y-1.5">
                      <Bond.checkbox
                        :for={tag <- @available_tags}
                        variant="pill_row"
                        checked={@selected_expense.tags |> Enum.member?(tag.label)}
                      >
                        <span
                          class="w-2.5 h-2.5 rounded-full shrink-0"
                          style={"background: #{tag_swatch(tag.label)}"}
                        />
                        <span class="text-sm text-surface-200">
                          {tag.label}
                        </span>
                      </Bond.checkbox>
                    </div>
                  </div>
                </div>
                <:footer>
                  <button class="text-sm font-bold text-error-400 hover:text-error-300 transition-colors">
                    Delete
                  </button>
                  <Bond.button>Save</Bond.button>
                </:footer>
              </Bond.side_panel>
            <% end %>
          </div>
        </Bond.desktop_window>
      </div>
    </div>
    """
  end

  defp grid_chart_placeholder(assigns) do
    ~H"""
    <div class="mx-4 mt-4 mb-3 bond-grid rounded-lg border border-surface-200 shadow-md shadow-primary-500/20 px-6 py-5">
      <div class="flex items-end gap-2 h-24">
        <div class="flex-1 bond-ink-bar rounded-t-sm opacity-90" style="height: 75%"></div>
        <div class="flex-1 bond-ink-bar rounded-t-sm opacity-60" style="height: 41%"></div>
        <div class="flex-1 bond-ink-bar rounded-t-sm opacity-75" style="height: 58%"></div>
        <div class="flex-1 bond-ink-bar rounded-t-sm opacity-50" style="height: 21%"></div>
        <div class="flex-1 bond-ink-bar rounded-t-sm opacity-65" style="height: 33%"></div>
      </div>
    </div>
    """
  end

  defp to_date_input(date) do
    case String.split(date, "/") do
      [m, d, y] -> "#{y}-#{m}-#{d}"
      _ -> date
    end
  end

  # The demo row now shows a single Category (ADR 0005); collapse the old tag list
  # to its first tag as a stand-in until the demo is reworked for categories (#70).
  defp demo_category([]), do: nil
  defp demo_category([label | _rest]), do: label

  defp tag_swatch(label) do
    case label do
      "kids" -> "var(--color-warning-400)"
      "food" -> "var(--color-error-400)"
      "groceries" -> "var(--color-primary-500)"
      "dining" -> "var(--color-success-400)"
      "sports" -> "var(--color-secondary-400)"
      _ -> "var(--color-surface-500)"
    end
  end
end
