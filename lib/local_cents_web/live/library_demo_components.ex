defmodule LocalCentsWeb.LibraryDemoComponents do
  @moduledoc "Demo component styles used by the library demo live view."

  use LocalCentsWeb, :html

  @spec simple_style(map()) :: Phoenix.LiveView.Rendered.t()
  def simple_style(assigns) do
    ~H"""
    <%!-- Library Window --%>
    <div
      id="simple-library-window"
      class="bg-white rounded-2xl shadow-2xl border border-gray-200 overflow-hidden"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-gray-100 border-b border-gray-200 select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-gray-500 pointer-events-none">
          Library
        </span>
      </div>
      <div class="m-4 border border-gray-300 bg-gray-50 rounded overflow-hidden">
        <div class="overflow-y-auto" style="min-height: 220px; max-height: 320px;">
          <%= for book <- @books do %>
            <div class="flex items-center gap-4 px-4 py-4 bg-white border-b border-gray-200 hover:bg-slate-50 transition-colors">
              <div class="flex-1 min-w-0">
                <p class="text-base font-semibold text-gray-900 leading-snug">
                  {book.name}
                </p>
                <p class="text-xs text-gray-400 mt-0.5">
                  Last Updated: {book.last_updated}
                </p>
              </div>
              <button class="flex-shrink-0 px-3 py-1 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 font-medium transition-colors shadow-sm">
                Open
              </button>
            </div>
          <% end %>
          <div class="h-16 bg-gray-50 border-b border-gray-200"></div>
        </div>
      </div>
      <div class="flex items-center justify-between px-4 py-4 border-t border-gray-200 bg-white">
        <button class="px-3 py-1 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 text-gray-700 transition-colors shadow-sm">
          New Book
        </button>
        <button class="w-7 h-7 rounded-full border border-gray-400 flex items-center justify-center text-gray-500 hover:bg-gray-100 text-sm font-semibold transition-colors shadow-sm leading-none">
          ?
        </button>
      </div>
    </div>

    <%!-- Simple Document Window --%>
    <div
      id="simple-document-window"
      class="relative bg-white rounded-2xl shadow-2xl border border-gray-200 overflow-hidden"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-gray-100 border-b border-gray-200 select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-90 transition-all border border-black/10 shadow-sm">
          </button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-gray-500 pointer-events-none">
          Family Expenses
        </span>
      </div>
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
      <div class="mx-4 mb-4 border border-gray-200 rounded-lg overflow-hidden">
        <div class="px-3 py-2.5 border-b border-gray-200 bg-gray-50">
          <%= if @show_new_expense do %>
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
          <% else %>
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
        <div class="h-12 bg-white"></div>
      </div>
      <%= if @selected_expense do %>
        <div id="expense-edit-panel" class="absolute inset-0 flex">
          <div class="flex-1 bg-gray-900/40" phx-click="close_expense"></div>
          <div class="w-80 bg-gray-50 border-l border-gray-200 flex flex-col shadow-xl">
            <div class="flex justify-end px-5 pt-5">
              <button
                phx-click="close_expense"
                class="text-gray-500 hover:text-gray-900 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>
            </div>
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
    """
  end

  @spec warm_style(map()) :: Phoenix.LiveView.Rendered.t()
  def warm_style(assigns) do
    ~H"""
    <%!-- Warm Library Window --%>
    <div
      id="warm-library-window"
      class="bg-[#F6F1E8] rounded-xl shadow-lg border border-[#C5B89A] overflow-hidden"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-[#EBE4D8] border-b border-[#C5B89A] select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/10"></button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/10"></button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/10"></button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-[#6B5544] pointer-events-none">
          Library
        </span>
      </div>
      <div class="m-4 border border-[#C5B89A] bg-[#FAF7F0] rounded overflow-hidden">
        <div class="overflow-y-auto" style="min-height: 220px; max-height: 320px;">
          <%= for book <- @books do %>
            <div class="flex items-center gap-4 px-4 py-4 bg-[#FAF7F0] border-b border-[#DDD5C5] hover:bg-[#F0E8DB] transition-colors">
              <div class="flex-1 min-w-0">
                <p class="text-base font-semibold text-[#2A1F14] leading-snug">
                  {book.name}
                </p>
                <p class="text-xs text-[#8C7557] mt-0.5">
                  Last Updated: {book.last_updated}
                </p>
              </div>
              <button class="flex-shrink-0 px-3 py-1 text-sm border border-[#C4622D] rounded text-[#C4622D] hover:bg-[#C4622D]/10 font-medium transition-colors">
                Open
              </button>
            </div>
          <% end %>
          <div class="h-16 bg-[#F0E8DB]"></div>
        </div>
      </div>
      <div class="flex items-center justify-between px-4 py-4 border-t border-[#C5B89A] bg-[#EBE4D8]">
        <button class="px-3 py-1 text-sm border border-[#C4622D] rounded text-[#C4622D] hover:bg-[#C4622D]/10 font-medium transition-colors">
          New Book
        </button>
        <button class="w-7 h-7 rounded-full border border-[#C4622D] flex items-center justify-center text-[#C4622D] hover:bg-[#C4622D]/10 text-sm font-semibold transition-colors leading-none">
          ?
        </button>
      </div>
    </div>

    <%!-- Warm Document Window --%>
    <div
      id="warm-document-window"
      class="relative bg-[#F6F1E8] rounded-xl shadow-lg border border-[#C5B89A] overflow-hidden"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-[#EBE4D8] border-b border-[#C5B89A] select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/10"></button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/10"></button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/10"></button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-[#6B5544] pointer-events-none">
          Family Expenses
        </span>
      </div>
      <%!-- Warm charts: horizontal category breakdown --%>
      <div class="m-4 bg-[#E8E1D3] rounded-lg border border-[#C5B89A] px-6 py-5">
        <p class="text-xs font-bold uppercase tracking-widest text-[#8C7557] mb-4">
          Spending by Category
        </p>
        <div class="space-y-3">
          <div class="flex items-center gap-3">
            <span class="text-xs text-[#8C7557] w-20 text-right shrink-0">Food</span>
            <div class="flex-1 bg-[#F6F1E8] rounded-full h-2">
              <div class="bg-[#C4622D] rounded-full h-2" style="width: 68%"></div>
            </div>
            <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">$247.89</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-xs text-[#8C7557] w-20 text-right shrink-0">Sports</span>
            <div class="flex-1 bg-[#F6F1E8] rounded-full h-2">
              <div class="bg-[#C4622D]/70 rounded-full h-2" style="width: 35%"></div>
            </div>
            <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">$135.00</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-xs text-[#8C7557] w-20 text-right shrink-0">Kids</span>
            <div class="flex-1 bg-[#F6F1E8] rounded-full h-2">
              <div class="bg-[#C4622D]/50 rounded-full h-2" style="width: 22%"></div>
            </div>
            <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">$67.50</span>
          </div>
        </div>
      </div>
      <%!-- Warm expense table --%>
      <div class="mx-4 mb-4 border border-[#C5B89A] rounded-lg overflow-hidden">
        <div class="px-3 py-2.5 border-b border-[#C5B89A] bg-[#EEE8DA]">
          <%= if @show_new_expense do %>
            <div class="flex items-center gap-2">
              <input
                id="warm-new-expense-input"
                type="text"
                autofocus
                class="flex-1 px-3 py-1.5 text-sm border border-[#C5B89A] rounded bg-[#FAF7F0] text-[#2A1F14] focus:outline-none focus:ring-2 focus:ring-[#C4622D]/40 focus:border-[#C4622D] placeholder-[#B8A88A]"
              />
              <button
                id="warm-new-expense-toggle-btn"
                phx-click="toggle_new_expense"
                class="flex-shrink-0 px-3 py-1.5 text-sm border border-[#C4622D] rounded text-[#C4622D] hover:bg-[#C4622D]/10 font-medium transition-colors"
              >
                New Expense
              </button>
            </div>
            <p class="mt-1.5 text-xs text-[#8C7557] pl-0.5">
              Type a phrase like "coffee 4.75" or "netflix 22.99 yesterday"
            </p>
          <% else %>
            <div class="flex items-center gap-2">
              <div class="relative">
                <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none">
                  <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5 text-[#8C7557]" />
                </div>
                <input
                  id="warm-expense-search-input"
                  type="text"
                  placeholder="search"
                  class="pl-7 pr-3 py-1.5 text-sm border border-[#C5B89A] rounded-full bg-[#FAF7F0] text-[#2A1F14] placeholder-[#B8A88A] focus:outline-none focus:ring-1 focus:ring-[#C4622D]/50 w-44"
                />
              </div>
              <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-[#6B5544] hover:bg-[#DDD5C5] rounded transition-colors">
                Tags <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
              </button>
              <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-[#6B5544] hover:bg-[#DDD5C5] rounded transition-colors">
                ↕ Newest <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
              </button>
              <div class="flex-1"></div>
              <button
                id="warm-expense-new-btn"
                phx-click="toggle_new_expense"
                class="flex-shrink-0 px-3 py-1.5 text-sm bg-[#C4622D] hover:bg-[#A8501E] text-white rounded font-medium transition-colors shadow-sm"
              >
                New Expense
              </button>
            </div>
          <% end %>
        </div>
        <%= for expense <- @expenses do %>
          <div
            id={"warm-expense-row-#{expense.id}"}
            phx-click="select_expense"
            phx-value-id={expense.id}
            class="flex items-center gap-4 px-4 py-3.5 border-b border-[#E4DBD0] hover:bg-[#F0E8DB] transition-colors cursor-pointer"
          >
            <span class="flex-shrink-0 text-sm text-[#8C7557] tabular-nums w-24">
              {expense.date}
            </span>
            <span class="flex-1 text-sm font-medium text-[#2A1F14]">
              {expense.description}
            </span>
            <div class="flex items-center gap-1.5">
              <%= for tag <- expense.tags do %>
                <span class={[
                  "px-2.5 py-0.5 text-xs font-medium rounded-full",
                  tag_class("warm", tag.label)
                ]}>
                  {tag.label}
                </span>
              <% end %>
            </div>
            <span class="flex-shrink-0 text-sm font-semibold text-[#C4622D] tabular-nums w-16 text-right">
              {expense.amount}
            </span>
          </div>
        <% end %>
        <div class="h-12 bg-[#FAF7F0]"></div>
      </div>
      <%!-- Warm edit panel --%>
      <%= if @selected_expense do %>
        <div id="warm-expense-edit-panel" class="absolute inset-0 flex">
          <div class="flex-1 bg-[#2A1F14]/40" phx-click="close_expense"></div>
          <div class="w-80 bg-[#EBE4D8] border-l border-[#C5B89A] flex flex-col shadow-xl">
            <div class="flex justify-end px-5 pt-5">
              <button
                phx-click="close_expense"
                class="text-[#8C7557] hover:text-[#2A1F14] transition-colors"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>
            </div>
            <div class="px-6 pt-2 pb-4 flex-1 space-y-5 overflow-y-auto">
              <div>
                <label class="block text-xs font-bold uppercase tracking-widest text-[#8C7557] mb-1.5">
                  Date
                </label>
                <input
                  type="date"
                  value={to_date_input(@selected_expense.date)}
                  class="w-full px-3 py-2 text-sm border border-[#C5B89A] rounded bg-[#FAF7F0] text-[#2A1F14] focus:outline-none focus:ring-2 focus:ring-[#C4622D]/40 focus:border-[#C4622D]"
                />
              </div>
              <div>
                <label class="block text-xs font-bold uppercase tracking-widest text-[#8C7557] mb-1.5">
                  Description
                </label>
                <input
                  type="text"
                  value={@selected_expense.description}
                  class="w-full px-3 py-2 text-sm border border-[#C5B89A] rounded bg-[#FAF7F0] text-[#2A1F14] focus:outline-none focus:ring-2 focus:ring-[#C4622D]/40 focus:border-[#C4622D]"
                />
              </div>
              <div>
                <label class="block text-xs font-bold uppercase tracking-widest text-[#8C7557] mb-1.5">
                  Cost
                </label>
                <input
                  type="text"
                  value={@selected_expense.amount}
                  class="w-full px-3 py-2 text-sm border border-[#C5B89A] rounded bg-[#FAF7F0] text-[#2A1F14] focus:outline-none focus:ring-2 focus:ring-[#C4622D]/40 focus:border-[#C4622D]"
                />
              </div>
              <div>
                <label class="block text-xs font-bold uppercase tracking-widest text-[#8C7557] mb-2.5">
                  Tags
                </label>
                <div class="space-y-2.5">
                  <%= for tag <- @available_tags do %>
                    <label class="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={Enum.any?(@selected_expense.tags, &(&1.label == tag.label))}
                        class="w-4 h-4 rounded border-[#C5B89A] text-[#C4622D] focus:ring-[#C4622D]"
                      />
                      <span class={[
                        "px-2.5 py-0.5 text-xs font-medium rounded-full",
                        tag_class("warm", tag.label)
                      ]}>
                        {tag.label}
                      </span>
                    </label>
                  <% end %>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-between px-6 py-4 border-t border-[#C5B89A] bg-[#E5DDD0]">
              <button class="text-sm font-medium text-red-700 hover:text-red-900 transition-colors">
                Delete
              </button>
              <button class="px-5 py-2 text-sm font-semibold text-white bg-[#C4622D] hover:bg-[#A8501E] rounded transition-colors shadow-sm">
                Save
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @spec dark_style(map()) :: Phoenix.LiveView.Rendered.t()
  def dark_style(assigns) do
    ~H"""
    <%!-- Dark Library Window --%>
    <div
      id="dark-library-window"
      class="bg-[#161B22] rounded-2xl border border-[#30363D] overflow-hidden shadow-2xl shadow-black/50"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-[#0D1117] border-b border-[#30363D] select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/20"></button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/20"></button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/20"></button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-[#8B949E] pointer-events-none">
          Library
        </span>
      </div>
      <div class="m-4 border border-[#21262D] bg-[#0D1117] rounded overflow-hidden">
        <div class="overflow-y-auto" style="min-height: 220px; max-height: 320px;">
          <%= for book <- @books do %>
            <div class="flex items-center gap-4 px-4 py-4 border-b border-[#21262D] hover:bg-[#1C2130] transition-colors">
              <div class="flex-1 min-w-0">
                <p class="text-base font-semibold text-[#E6EDF3] leading-snug">
                  {book.name}
                </p>
                <p class="text-xs text-[#6E7681] mt-0.5">
                  Last Updated: {book.last_updated}
                </p>
              </div>
              <button class="flex-shrink-0 px-3 py-1 text-sm border border-[#444C56] rounded bg-[#21262D] hover:bg-[#2D333B] text-[#C9D1D9] font-medium transition-colors">
                Open
              </button>
            </div>
          <% end %>
          <div class="h-16 bg-[#0D1117]"></div>
        </div>
      </div>
      <div class="flex items-center justify-between px-4 py-4 border-t border-[#30363D] bg-[#0D1117]">
        <button class="px-3 py-1 text-sm border border-[#444C56] rounded bg-[#21262D] hover:bg-[#2D333B] text-[#C9D1D9] transition-colors">
          New Book
        </button>
        <button class="w-7 h-7 rounded-full border border-[#444C56] flex items-center justify-center text-[#8B949E] hover:bg-[#21262D] text-sm font-semibold transition-colors leading-none">
          ?
        </button>
      </div>
    </div>

    <%!-- Dark Document Window --%>
    <div
      id="dark-document-window"
      class="relative bg-[#161B22] rounded-2xl border border-[#30363D] overflow-hidden shadow-2xl shadow-black/50"
    >
      <div class="relative flex items-center pl-3 pr-4 py-2 bg-[#0D1117] border-b border-[#30363D] select-none">
        <div class="flex items-center gap-2 z-10">
          <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/20"></button>
          <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/20"></button>
          <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/20"></button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-[#8B949E] pointer-events-none">
          Family Expenses
        </span>
      </div>
      <%!-- Dark charts: vertical bars --%>
      <div class="m-4 bg-[#0D1117] rounded-lg border border-[#21262D] px-6 py-5">
        <p class="text-xs font-mono uppercase tracking-widest text-[#6E7681] mb-4">
          Spending Overview
        </p>
        <div class="grid grid-cols-3 gap-6 h-24">
          <div class="flex items-end gap-1">
            <div class="flex-1 bg-indigo-600/40 rounded-t" style="height: 55%"></div>
            <div class="flex-1 bg-indigo-500/60 rounded-t" style="height: 80%"></div>
            <div class="flex-1 bg-indigo-600/40 rounded-t" style="height: 40%"></div>
            <div class="flex-1 bg-indigo-500/60 rounded-t" style="height: 70%"></div>
          </div>
          <div class="flex items-end gap-1">
            <div class="flex-1 bg-violet-600/40 rounded-t" style="height: 70%"></div>
            <div class="flex-1 bg-violet-500/60 rounded-t" style="height: 50%"></div>
            <div class="flex-1 bg-violet-600/40 rounded-t" style="height: 85%"></div>
            <div class="flex-1 bg-violet-500/60 rounded-t" style="height: 45%"></div>
          </div>
          <div class="flex items-end gap-1">
            <div class="flex-1 bg-emerald-600/40 rounded-t" style="height: 40%"></div>
            <div class="flex-1 bg-emerald-500/60 rounded-t" style="height: 75%"></div>
            <div class="flex-1 bg-emerald-600/40 rounded-t" style="height: 90%"></div>
            <div class="flex-1 bg-emerald-500/60 rounded-t" style="height: 55%"></div>
          </div>
        </div>
      </div>
      <%!-- Dark expense table --%>
      <div class="mx-4 mb-4 border border-[#30363D] rounded-lg overflow-hidden">
        <div class="px-3 py-2.5 border-b border-[#30363D] bg-[#0D1117]">
          <%= if @show_new_expense do %>
            <div class="flex items-center gap-2">
              <input
                id="dark-new-expense-input"
                type="text"
                autofocus
                class="flex-1 px-3 py-1.5 text-sm border border-[#444C56] rounded bg-[#0D1117] text-[#E6EDF3] focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500 placeholder-[#6E7681]"
              />
              <button
                id="dark-new-expense-toggle-btn"
                phx-click="toggle_new_expense"
                class="flex-shrink-0 px-3 py-1.5 text-sm border border-[#444C56] rounded bg-[#21262D] hover:bg-[#2D333B] text-[#C9D1D9] font-medium transition-colors"
              >
                New Expense
              </button>
            </div>
            <p class="mt-1.5 text-xs text-[#6E7681] pl-0.5">
              Type a phrase like "coffee 4.75" or "netflix 22.99 yesterday"
            </p>
          <% else %>
            <div class="flex items-center gap-2">
              <div class="relative">
                <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none">
                  <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5 text-[#6E7681]" />
                </div>
                <input
                  id="dark-expense-search-input"
                  type="text"
                  placeholder="search"
                  class="pl-7 pr-3 py-1.5 text-sm border border-[#444C56] rounded-full bg-[#0D1117] text-[#C9D1D9] placeholder-[#6E7681] focus:outline-none focus:ring-1 focus:ring-indigo-500 w-44"
                />
              </div>
              <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-[#8B949E] hover:text-[#E6EDF3] hover:bg-[#21262D] rounded transition-colors">
                Tags <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
              </button>
              <button class="flex items-center gap-1 px-2.5 py-1.5 text-sm text-[#8B949E] hover:text-[#E6EDF3] hover:bg-[#21262D] rounded transition-colors">
                ↕ Newest <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
              </button>
              <div class="flex-1"></div>
              <button
                id="dark-expense-new-btn"
                phx-click="toggle_new_expense"
                class="flex-shrink-0 px-3 py-1.5 text-sm bg-indigo-600 hover:bg-indigo-500 text-white rounded font-medium transition-colors"
              >
                New Expense
              </button>
            </div>
          <% end %>
        </div>
        <%= for expense <- @expenses do %>
          <div
            id={"dark-expense-row-#{expense.id}"}
            phx-click="select_expense"
            phx-value-id={expense.id}
            class="flex items-center gap-4 px-4 py-3.5 border-b border-[#21262D] hover:bg-[#1C2130] transition-colors cursor-pointer"
          >
            <span class="flex-shrink-0 text-sm text-[#6E7681] tabular-nums font-mono w-24">
              {expense.date}
            </span>
            <span class="flex-1 text-sm font-medium text-[#E6EDF3]">
              {expense.description}
            </span>
            <div class="flex items-center gap-1.5">
              <%= for tag <- expense.tags do %>
                <span class={[
                  "px-2.5 py-0.5 text-xs font-medium rounded-full",
                  tag_class("dark", tag.label)
                ]}>
                  {tag.label}
                </span>
              <% end %>
            </div>
            <span class="flex-shrink-0 text-sm font-semibold text-emerald-400 tabular-nums font-mono w-16 text-right">
              {expense.amount}
            </span>
          </div>
        <% end %>
        <div class="h-12 bg-[#161B22]"></div>
      </div>
      <%!-- Dark edit panel --%>
      <%= if @selected_expense do %>
        <div id="dark-expense-edit-panel" class="absolute inset-0 flex">
          <div class="flex-1 bg-black/60" phx-click="close_expense"></div>
          <div class="w-80 bg-[#0D1117] border-l border-[#30363D] flex flex-col shadow-2xl">
            <div class="flex justify-end px-5 pt-5">
              <button
                phx-click="close_expense"
                class="text-[#6E7681] hover:text-[#E6EDF3] transition-colors"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>
            </div>
            <div class="px-6 pt-2 pb-4 flex-1 space-y-5 overflow-y-auto">
              <div>
                <label class="block text-xs font-mono uppercase tracking-widest text-[#6E7681] mb-1.5">
                  Date
                </label>
                <input
                  type="date"
                  value={to_date_input(@selected_expense.date)}
                  class="w-full px-3 py-2 text-sm border border-[#444C56] rounded bg-[#161B22] text-[#E6EDF3] focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                />
              </div>
              <div>
                <label class="block text-xs font-mono uppercase tracking-widest text-[#6E7681] mb-1.5">
                  Description
                </label>
                <input
                  type="text"
                  value={@selected_expense.description}
                  class="w-full px-3 py-2 text-sm border border-[#444C56] rounded bg-[#161B22] text-[#E6EDF3] focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                />
              </div>
              <div>
                <label class="block text-xs font-mono uppercase tracking-widest text-[#6E7681] mb-1.5">
                  Cost
                </label>
                <input
                  type="text"
                  value={@selected_expense.amount}
                  class="w-full px-3 py-2 text-sm border border-[#444C56] rounded bg-[#161B22] text-[#E6EDF3] focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                />
              </div>
              <div>
                <label class="block text-xs font-mono uppercase tracking-widest text-[#6E7681] mb-2.5">
                  Tags
                </label>
                <div class="space-y-2.5">
                  <%= for tag <- @available_tags do %>
                    <label class="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={Enum.any?(@selected_expense.tags, &(&1.label == tag.label))}
                        class="w-4 h-4 rounded border-[#444C56] bg-[#161B22] text-indigo-500 focus:ring-indigo-500 focus:ring-offset-[#0D1117]"
                      />
                      <span class={[
                        "px-2.5 py-0.5 text-xs font-medium rounded-full",
                        tag_class("dark", tag.label)
                      ]}>
                        {tag.label}
                      </span>
                    </label>
                  <% end %>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-between px-6 py-4 border-t border-[#30363D] bg-[#0D1117]">
              <button class="text-sm font-medium text-red-400 hover:text-red-300 transition-colors">
                Delete
              </button>
              <button class="px-5 py-2 text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded transition-colors shadow-sm">
                Save
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp to_date_input(date) do
    case String.split(date, "/") do
      [m, d, y] -> "#{y}-#{m}-#{d}"
      _ -> date
    end
  end

  defp tag_class("warm", label) do
    case label do
      "kids" -> "bg-amber-100 text-amber-800 border border-amber-200"
      "food" -> "bg-orange-100 text-orange-800 border border-orange-200"
      "groceries" -> "bg-lime-100 text-lime-800 border border-lime-200"
      "dining" -> "bg-rose-100 text-rose-800 border border-rose-200"
      "sports" -> "bg-teal-100 text-teal-800 border border-teal-200"
      _ -> "bg-stone-100 text-stone-700 border border-stone-200"
    end
  end

  defp tag_class("dark", label) do
    case label do
      "kids" -> "bg-sky-950 text-sky-400 border border-sky-800"
      "food" -> "bg-orange-950 text-orange-400 border border-orange-800"
      "groceries" -> "bg-violet-950 text-violet-400 border border-violet-800"
      "dining" -> "bg-emerald-950 text-emerald-400 border border-emerald-800"
      "sports" -> "bg-rose-950 text-rose-400 border border-rose-800"
      _ -> "bg-gray-800 text-gray-400 border border-gray-700"
    end
  end

  defp tag_class(_, _), do: "bg-gray-100 text-gray-700 border border-gray-200"
end
