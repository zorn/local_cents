defmodule LocalCentsWeb.LibraryDemoLive do
  use LocalCentsWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    books = [
      %{id: 1, name: "Family Expenses", last_updated: "06-02-2026 1:34 PM"},
      %{id: 2, name: "Side Hustle LLC Expenses", last_updated: "06-02-2026 1:34 PM"}
    ]

    available_tags = [
      %{label: "kids", class: "bg-sky-100 text-sky-700 border border-sky-200"},
      %{label: "some-long-tag-name", class: "bg-purple-100 text-purple-700 border border-purple-200"},
      %{label: "food", class: "bg-orange-100 text-orange-700 border border-orange-200"},
      %{label: "sports", class: "bg-red-100 text-red-700 border border-red-200"},
      %{label: "groceries", class: "bg-purple-100 text-purple-700 border border-purple-200"},
      %{label: "dining", class: "bg-green-100 text-green-700 border border-green-200"}
    ]

    expenses = [
      %{
        id: 1,
        date: "06/01/2026",
        description: "Whole Foods grocery run",
        tags: [
          %{label: "groceries", class: "bg-purple-100 text-purple-700 border border-purple-200"},
          %{label: "food", class: "bg-orange-100 text-orange-700 border border-orange-200"}
        ],
        amount: "$127.43"
      },
      %{
        id: 2,
        date: "05/30/2026",
        description: "Dinner at Olive Garden",
        tags: [
          %{label: "dining", class: "bg-green-100 text-green-700 border border-green-200"}
        ],
        amount: "$67.50"
      },
      %{
        id: 3,
        date: "05/28/2026",
        description: "Summer soccer registration",
        tags: [
          %{label: "kids", class: "bg-sky-100 text-sky-700 border border-sky-200"},
          %{label: "sports", class: "bg-red-100 text-red-700 border border-red-200"}
        ],
        amount: "$67.50"
      }
    ]

    {:ok,
     assign(socket,
       books: books,
       available_tags: available_tags,
       expenses: expenses,
       show_new_expense: false,
       selected_expense: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_new_expense", _, socket) do
    {:noreply, assign(socket, show_new_expense: !socket.assigns.show_new_expense)}
  end

  def handle_event("select_expense", %{"id" => id}, socket) do
    expense = Enum.find(socket.assigns.expenses, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, selected_expense: expense)}
  end

  def handle_event("close_expense", _, socket) do
    {:noreply, assign(socket, selected_expense: nil)}
  end

  defp to_date_input(date) do
    case String.split(date, "/") do
      [m, d, y] -> "#{y}-#{m}-#{d}"
      _ -> date
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="py-6 space-y-8">
        <%!-- Library Window --%>
        <div class="bg-white rounded-2xl shadow-2xl border border-gray-200 overflow-hidden">
          <%!-- macOS Title Bar --%>
          <div class="relative flex items-center px-4 py-3 bg-gray-100 border-b border-gray-200 select-none">
            <div class="flex items-center gap-2 z-10">
              <button class="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
              <button class="w-3 h-3 rounded-full bg-[#FEBC2E] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
              <button class="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
            </div>
            <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-gray-500 pointer-events-none">
              Library
            </span>
          </div>

          <%!-- Book List --%>
          <div class="m-4 border border-gray-300 bg-gray-50 rounded overflow-hidden">
            <div class="overflow-y-auto" style="min-height: 220px; max-height: 320px;">
              <%= for book <- @books do %>
                <div class="flex items-center gap-4 px-4 py-4 bg-white border-b border-gray-200 hover:bg-slate-50 transition-colors">
                  <div class="flex-1 min-w-0">
                    <p class="text-base font-semibold text-gray-900 leading-snug">{book.name}</p>
                    <p class="text-xs text-gray-400 mt-0.5">Last Updated: {book.last_updated}</p>
                  </div>
                  <button class="flex-shrink-0 px-3 py-1 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 font-medium transition-colors shadow-sm">
                    Open
                  </button>
                </div>
              <% end %>
              <div class="h-16 bg-gray-50 border-b border-gray-200"></div>
            </div>
          </div>

          <%!-- Footer --%>
          <div class="flex items-center justify-between px-4 py-4 border-t border-gray-200 bg-white">
            <button class="px-3 py-1 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 transition-colors shadow-sm">
              New Book
            </button>
            <button class="w-7 h-7 rounded-full border border-gray-400 flex items-center justify-center text-gray-500 hover:bg-gray-100 text-sm font-semibold transition-colors shadow-sm leading-none">
              ?
            </button>
          </div>
        </div>

        <%!-- Book Document Window --%>
        <div class="relative bg-white rounded-2xl shadow-2xl border border-gray-200 overflow-hidden">
          <%!-- macOS Title Bar --%>
          <div class="relative flex items-center px-4 py-3 bg-gray-100 border-b border-gray-200 select-none">
            <div class="flex items-center gap-2 z-10">
              <button class="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
              <button class="w-3 h-3 rounded-full bg-[#FEBC2E] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
              <button class="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-90 transition-all border border-black/10 shadow-sm"></button>
            </div>
            <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-gray-500 pointer-events-none">
              Family Expenses
            </span>
          </div>

          <%!-- Charts Placeholder --%>
          <div class="m-4 bg-gray-100 rounded-lg border border-gray-200 p-5">
            <div class="grid grid-cols-3 gap-8">
              <div class="space-y-2">
                <div class="h-2.5 bg-gray-300 rounded-sm w-[55%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[80%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[40%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[70%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[60%]"></div>
              </div>
              <div class="space-y-2">
                <div class="h-2.5 bg-gray-300 rounded-sm w-[70%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[50%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[85%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[45%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[65%]"></div>
              </div>
              <div class="space-y-2">
                <div class="h-2.5 bg-gray-300 rounded-sm w-[40%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[75%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[90%]"></div>
                <div class="h-2.5 bg-gray-400 rounded-sm w-[55%]"></div>
                <div class="h-2.5 bg-gray-300 rounded-sm w-[70%]"></div>
              </div>
            </div>
          </div>

          <%!-- Expense Table --%>
          <div class="mx-4 mb-4 border border-gray-200 rounded-lg overflow-hidden">
            <%!-- Toolbar --%>
            <div class="px-3 py-2.5 border-b border-gray-200 bg-gray-50">
              <%= if @show_new_expense do %>
                <%!-- New Expense Input --%>
                <div>
                  <div class="flex items-center gap-2">
                    <input
                      id="new-expense-input"
                      type="text"
                      autofocus
                      class="flex-1 px-3 py-1.5 text-sm border border-gray-400 rounded bg-white focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent placeholder-gray-300"
                    />
                    <button
                      id="new-expense-toggle-btn"
                      phx-click="toggle_new_expense"
                      class="flex-shrink-0 px-3 py-1.5 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 font-medium transition-colors"
                    >
                      New Expense
                    </button>
                  </div>
                  <p class="mt-1.5 text-xs text-gray-400 pl-0.5">
                    Type a phrase like "coffee 4.75" or "netflix 22.99 yesterday"
                  </p>
                </div>
              <% else %>
                <%!-- Search / Filter Toolbar --%>
                <div class="flex items-center gap-2">
                  <div class="relative">
                    <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none">
                      <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5 text-gray-400" />
                    </div>
                    <input
                      id="expense-search-input"
                      type="text"
                      placeholder="search"
                      class="pl-7 pr-3 py-1.5 text-sm border border-gray-300 rounded-full bg-white focus:outline-none focus:ring-1 focus:ring-gray-400 text-gray-700 placeholder-gray-400 w-44"
                    />
                  </div>
                  <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-gray-600 hover:bg-gray-200 rounded transition-colors">
                    Tags <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
                  </button>
                  <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-gray-600 hover:bg-gray-200 rounded transition-colors">
                    ↕ Newest <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
                  </button>
                  <div class="flex-1"></div>
                  <button
                    id="expense-new-btn"
                    phx-click="toggle_new_expense"
                    class="flex-shrink-0 px-3 py-1.5 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 font-medium transition-colors"
                  >
                    New Expense
                  </button>
                </div>
              <% end %>
            </div>

            <%!-- Expense Rows --%>
            <%= for expense <- @expenses do %>
              <div
                id={"expense-row-#{expense.id}"}
                phx-click="select_expense"
                phx-value-id={expense.id}
                class="flex items-center gap-4 px-4 py-3.5 border-b border-gray-100 hover:bg-gray-50 transition-colors cursor-pointer"
              >
                <span class="flex-shrink-0 text-sm text-gray-500 tabular-nums w-24">
                  {expense.date}
                </span>
                <span class="flex-1 text-sm font-medium text-gray-900">
                  {expense.description}
                </span>
                <div class="flex items-center gap-1.5">
                  <%= for tag <- expense.tags do %>
                    <span class={["px-2.5 py-0.5 text-xs font-medium rounded-full", tag.class]}>
                      {tag.label}
                    </span>
                  <% end %>
                </div>
                <span class="flex-shrink-0 text-sm font-semibold text-gray-800 tabular-nums w-16 text-right">
                  {expense.amount}
                </span>
              </div>
            <% end %>

            <%!-- Empty trailing row --%>
            <div class="h-12 bg-white"></div>
          </div>

          <%!-- Expense Edit Panel --%>
          <%= if @selected_expense do %>
            <div id="expense-edit-panel" class="absolute inset-0 flex">
              <%!-- Dimmed left overlay — click to close --%>
              <div
                class="flex-1 bg-gray-900/40"
                phx-click="close_expense"
              ></div>

              <%!-- Edit panel --%>
              <div class="w-80 bg-gray-50 border-l border-gray-200 flex flex-col shadow-xl">
                <%!-- Close button --%>
                <div class="flex justify-end px-5 pt-5">
                  <button
                    phx-click="close_expense"
                    class="text-gray-500 hover:text-gray-900 transition-colors"
                  >
                    <.icon name="hero-x-mark" class="w-6 h-6" />
                  </button>
                </div>

                <%!-- Form fields --%>
                <div class="px-6 pt-2 pb-4 flex-1 space-y-5 overflow-y-auto">
                  <div>
                    <label class="block text-sm font-bold text-gray-900 mb-1.5">Date</label>
                    <input
                      type="date"
                      value={to_date_input(@selected_expense.date)}
                      class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-bold text-gray-900 mb-1.5">Description</label>
                    <input
                      type="text"
                      value={@selected_expense.description}
                      class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-bold text-gray-900 mb-1.5">Cost</label>
                    <input
                      type="text"
                      value={@selected_expense.amount}
                      class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-bold text-gray-900 mb-2.5">Tags</label>
                    <div class="space-y-2.5">
                      <%= for tag <- @available_tags do %>
                        <label class="flex items-center gap-3 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={Enum.any?(@selected_expense.tags, &(&1.label == tag.label))}
                            class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                          />
                          <span class={["px-2.5 py-0.5 text-xs font-medium rounded-full", tag.class]}>
                            {tag.label}
                          </span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                </div>

                <%!-- Footer: Delete + Save --%>
                <div class="flex items-center justify-between px-6 py-4 border-t border-gray-200 bg-gray-50">
                  <button class="text-sm font-medium text-red-500 hover:text-red-700 transition-colors">
                    Delete
                  </button>
                  <button class="px-5 py-2 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-md transition-colors shadow-sm">
                    Save
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
