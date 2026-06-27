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
      %{
        label: "some-long-tag-name",
        class: "bg-purple-100 text-purple-700 border border-purple-200"
      },
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
       selected_expense: nil,
       active_style: "simple",
       notebook_texture: "light"
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"style" => style}, _uri, socket)
      when style in ["simple", "warm", "dark", "notebook"] do
    {:noreply,
     assign(socket,
       active_style: style,
       show_new_expense: false,
       selected_expense: nil
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("switch_style", %{"style" => style}, socket) do
    {:noreply, push_patch(socket, to: ~p"/library-demo?style=#{style}")}
  end

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

  defp nb_tag_swatch(label) do
    case label do
      "kids" -> "#e6b53c"
      "food" -> "#e0796e"
      "groceries" -> "#3f7fd6"
      "dining" -> "#6fc59a"
      "sports" -> "#9b8bd6"
      _ -> "#8b9fc0"
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class={[
        "pb-12",
        @active_style == "warm" && "bg-[#E8E3D8]",
        @active_style == "dark" && "bg-[#0D1117]",
        @active_style == "notebook" && "bg-[#eef3fc]"
      ]}>
        <%!-- Style Navigator --%>
        <div class="pt-6 pb-6 flex justify-center">
          <div class={[
            "flex items-center gap-1 p-1 rounded-full",
            if(@active_style == "dark", do: "bg-white/10", else: "bg-black/10")
          ]}>
            <%= for {style_key, style_label} <- [{"simple", "Simple"}, {"warm", "Warm Ledger"}, {"dark", "Dark Slate"}, {"notebook", "Notebook"}] do %>
              <button
                id={"style-btn-#{style_key}"}
                phx-click="switch_style"
                phx-value-style={style_key}
                class={[
                  "px-5 py-2 rounded-full text-sm font-medium transition-all",
                  if(@active_style == style_key,
                    do:
                      if(@active_style == "dark",
                        do: "bg-white/20 text-white shadow-sm",
                        else: "bg-white text-gray-900 shadow-sm"
                      ),
                    else:
                      if(@active_style == "dark",
                        do: "text-gray-500 hover:text-gray-300",
                        else: "text-gray-600 hover:text-gray-900"
                      )
                  )
                ]}
              >
                {style_label}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Per-style content --%>
        <div class="space-y-8">
          <%= cond do %>
            <%!-- ═══════════════════════════════════════════════ SIMPLE STYLE ═══ --%>
            <% @active_style == "simple" -> %>
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
                          <label class="block text-sm font-bold text-gray-900 mb-1.5">
                            Description
                          </label>
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
                                  checked={
                                    Enum.any?(@selected_expense.tags, &(&1.label == tag.label))
                                  }
                                  class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                                <span class={[
                                  "px-2.5 py-0.5 text-xs font-medium rounded-full",
                                  tag.class
                                ]}>
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

              <%!-- ════════════════════════════════════════════ WARM LEDGER STYLE ═══ --%>
            <% @active_style == "warm" -> %>
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
                      <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">
                        $247.89
                      </span>
                    </div>
                    <div class="flex items-center gap-3">
                      <span class="text-xs text-[#8C7557] w-20 text-right shrink-0">Sports</span>
                      <div class="flex-1 bg-[#F6F1E8] rounded-full h-2">
                        <div class="bg-[#C4622D]/70 rounded-full h-2" style="width: 35%"></div>
                      </div>
                      <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">
                        $135.00
                      </span>
                    </div>
                    <div class="flex items-center gap-3">
                      <span class="text-xs text-[#8C7557] w-20 text-right shrink-0">Kids</span>
                      <div class="flex-1 bg-[#F6F1E8] rounded-full h-2">
                        <div class="bg-[#C4622D]/50 rounded-full h-2" style="width: 22%"></div>
                      </div>
                      <span class="text-xs font-semibold text-[#2A1F14] w-16 text-right shrink-0">
                        $67.50
                      </span>
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
                                  checked={
                                    Enum.any?(@selected_expense.tags, &(&1.label == tag.label))
                                  }
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

              <%!-- ═══════════════════════════════════════════════ DARK SLATE STYLE ═══ --%>
            <% @active_style == "dark" -> %>
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
                                  checked={
                                    Enum.any?(@selected_expense.tags, &(&1.label == tag.label))
                                  }
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

              <%!-- ══════════════════════════════════════════════ NOTEBOOK STYLE ═══ --%>
            <% @active_style == "notebook" -> %>
              <div class="space-y-6 nb-tint-sapphire">
                <%!-- Notebook Library Window --%>
                <div
                  id="notebook-library-window"
                  class={[
                    "rounded-xl overflow-hidden border border-[#a8c0e0] shadow-lg shadow-[#3f7fd6]/20",
                    "nb-tex-#{@notebook_texture}"
                  ]}
                >
                  <%!-- Denim marble title bar --%>
                  <div class="nb-denim relative flex items-center pl-3 pr-4 py-2 select-none border-b border-[#0d1a35]">
                    <div class="flex items-center gap-2 z-10">
                      <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/20">
                      </button>
                      <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/20">
                      </button>
                      <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/20">
                      </button>
                    </div>
                    <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-white/90 pointer-events-none">
                      Library
                    </span>
                  </div>
                  <%!-- Ruled paper book list --%>
                  <div class="m-4 bg-white rounded overflow-hidden border border-[#c3d2f0] shadow-md shadow-[#3f7fd6]/20">
                    <div class="overflow-y-auto" style="min-height: 220px; max-height: 320px;">
                      <%= for book <- @books do %>
                        <div class="flex items-center gap-4 px-4 py-4 border-b border-[#c3d2f0]/60 nb-t-hover-row transition-colors">
                          <div class="flex-1 min-w-0">
                            <p class="font-nunito text-base font-semibold text-[#22335c] leading-snug">
                              {book.name}
                            </p>
                            <p class="font-nunito text-xs text-[#6980b0] mt-0.5">
                              Last Updated: {book.last_updated}
                            </p>
                          </div>
                          <button class="font-nunito flex-shrink-0 px-3 py-1 text-sm border-2 nb-t-border rounded-full nb-t-text nb-t-hover-solid font-bold transition-all">
                            Open
                          </button>
                        </div>
                      <% end %>
                      <div class="h-16"></div>
                    </div>
                  </div>
                  <%!-- Footer --%>
                  <div class="flex items-center justify-between px-4 py-4">
                    <button class="font-nunito font-bold px-4 py-1.5 text-sm nb-t-bg nb-t-hover-dk text-white rounded-full transition-colors nb-t-shadow">
                      New Book
                    </button>
                    <button class="font-nunito w-7 h-7 rounded-full border-2 nb-t-border nb-t-bg-soft flex items-center justify-center nb-t-text nb-t-hover-soft text-sm font-bold transition-colors">
                      ?
                    </button>
                  </div>
                </div>

                <%!-- Notebook Document Window --%>
                <div
                  id="notebook-document-window"
                  class="relative bg-white rounded-xl overflow-hidden border border-[#c3d2f0] shadow-lg shadow-[#3f7fd6]/15"
                >
                  <%!-- Denim title bar --%>
                  <div class="nb-denim relative flex items-center pl-3 pr-4 py-2 select-none border-b border-[#0d1a35]">
                    <div class="flex items-center gap-2 z-10">
                      <button class="w-3 h-3 rounded-full bg-[#FF5F57] border border-black/20">
                      </button>
                      <button class="w-3 h-3 rounded-full bg-[#FEBC2E] border border-black/20">
                      </button>
                      <button class="w-3 h-3 rounded-full bg-[#28C840] border border-black/20">
                      </button>
                    </div>
                    <span class="absolute inset-0 flex items-center justify-center text-sm font-semibold text-white/90 pointer-events-none">
                      Family Expenses
                    </span>
                  </div>
                  <%!-- Graph paper chart placeholder --%>
                  <div class="m-4 nb-graph rounded-lg border border-[#c3d2f0] px-6 py-5">
                    <p class="font-caveat text-lg nb-t-text mb-4">where it all went →</p>
                    <div class="flex items-end gap-2 h-20 mb-3">
                      <div class="flex-1 flex flex-col justify-end items-center gap-1">
                        <span class="font-caveat text-sm text-[#22335c]">$247</span>
                        <div class="w-full nb-t-bar rounded-t-sm" style="height: 75%"></div>
                        <span class="font-nunito text-[9px] font-bold uppercase tracking-wider text-[#22335c] mt-1">
                          Food
                        </span>
                      </div>
                      <div class="flex-1 flex flex-col justify-end items-center gap-1">
                        <span class="font-caveat text-sm text-[#22335c]">$135</span>
                        <div class="w-full bg-[#9b8bd6]/70 rounded-t-sm" style="height: 41%"></div>
                        <span class="font-nunito text-[9px] font-bold uppercase tracking-wider text-[#22335c] mt-1">
                          Sports
                        </span>
                      </div>
                      <div class="flex-1 flex flex-col justify-end items-center gap-1">
                        <span class="font-caveat text-sm text-[#22335c]">$67</span>
                        <div class="w-full bg-[#e0796e]/70 rounded-t-sm" style="height: 21%"></div>
                        <span class="font-nunito text-[9px] font-bold uppercase tracking-wider text-[#22335c] mt-1">
                          Kids
                        </span>
                      </div>
                      <div class="flex-1 flex flex-col justify-end items-center gap-1">
                        <span class="font-caveat text-sm text-[#22335c]">$68</span>
                        <div class="w-full bg-[#6fc59a]/70 rounded-t-sm" style="height: 22%"></div>
                        <span class="font-nunito text-[9px] font-bold uppercase tracking-wider text-[#22335c] mt-1">
                          Dining
                        </span>
                      </div>
                      <div class="flex-1 flex flex-col justify-end items-center gap-1">
                        <span class="font-caveat text-sm text-[#22335c]">$44</span>
                        <div class="w-full bg-[#e6b53c]/70 rounded-t-sm" style="height: 14%"></div>
                        <span class="font-nunito text-[9px] font-bold uppercase tracking-wider text-[#22335c] mt-1">
                          Other
                        </span>
                      </div>
                    </div>
                    <div class="border-t border-[#c3d2f0] pt-2 flex justify-between items-baseline">
                      <span class="font-caveat text-base text-[#6980b0]">June, so far</span>
                      <span class="font-caveat text-xl text-[#22335c] font-semibold">$561.43</span>
                    </div>
                  </div>
                  <%!-- Ruled paper expense table --%>
                  <div class="mx-4 mb-4 nb-ruled rounded-lg border border-[#c3d2f0] overflow-hidden">
                    <%!-- Toolbar --%>
                    <div class="px-3 py-2.5 border-b border-[#c3d2f0] bg-white/90">
                      <%= if @show_new_expense do %>
                        <div class="flex items-center gap-2">
                          <input
                            id="notebook-new-expense-input"
                            type="text"
                            autofocus
                            placeholder="coffee 4.75 or netflix 22.99 yesterday"
                            class="font-nunito flex-1 px-3 py-1.5 text-sm border-b-2 nb-t-border bg-transparent focus:outline-none text-[#22335c] placeholder-[#a0b4d0]"
                          />
                          <button
                            id="notebook-new-expense-toggle-btn"
                            phx-click="toggle_new_expense"
                            class="font-nunito font-bold flex-shrink-0 px-4 py-1.5 text-sm border-2 nb-t-border rounded-full nb-t-text nb-t-hover-soft transition-colors"
                          >
                            New Expense
                          </button>
                        </div>
                      <% else %>
                        <div class="flex items-center gap-2">
                          <div class="relative">
                            <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none">
                              <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5 text-[#6980b0]" />
                            </div>
                            <input
                              id="notebook-expense-search-input"
                              type="text"
                              placeholder="search..."
                              class="font-nunito pl-7 pr-3 py-1.5 text-sm border-2 border-[#c3d2f0] rounded-full bg-white focus:outline-none nb-t-focus-border text-[#22335c] placeholder-[#a0b4d0] w-44 transition-colors"
                            />
                          </div>
                          <button class="font-nunito flex items-center gap-1 px-2.5 py-1.5 text-sm font-semibold nb-t-text nb-t-hover-soft rounded-full transition-colors">
                            Tags <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
                          </button>
                          <button class="font-nunito flex items-center gap-1 px-2.5 py-1.5 text-sm font-semibold nb-t-text nb-t-hover-soft rounded-full transition-colors">
                            ↕ Newest <.icon name="hero-chevron-down" class="w-3 h-3 mt-px" />
                          </button>
                          <div class="flex-1"></div>
                          <button
                            id="notebook-expense-new-btn"
                            phx-click="toggle_new_expense"
                            class="font-nunito font-bold flex-shrink-0 px-4 py-1.5 text-sm nb-t-bg nb-t-hover-dk text-white rounded-full transition-colors nb-t-shadow"
                          >
                            New Expense
                          </button>
                        </div>
                      <% end %>
                    </div>
                    <%!-- Expense Rows --%>
                    <%= for expense <- @expenses do %>
                      <div
                        id={"notebook-expense-row-#{expense.id}"}
                        phx-click="select_expense"
                        phx-value-id={expense.id}
                        class="flex items-center gap-4 px-4 py-3 border-b border-[#c3d2f0]/60 nb-t-hover-row transition-colors cursor-pointer"
                      >
                        <span class="flex-shrink-0 font-nunito text-sm text-[#6980b0] tabular-nums w-24">
                          {expense.date}
                        </span>
                        <span class="flex-1 font-nunito text-sm font-medium text-[#22335c]">
                          {expense.description}
                        </span>
                        <div class="flex items-center gap-1.5">
                          <%= for tag <- expense.tags do %>
                            <span class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold font-nunito bg-white border border-[#c3d2f0] text-[#22335c]">
                              <span
                                class="w-2 h-2 rounded-full flex-shrink-0"
                                style={"background: #{nb_tag_swatch(tag.label)}"}
                              >
                              </span>
                              {tag.label}
                            </span>
                          <% end %>
                        </div>
                        <span class="flex-shrink-0 font-nunito text-sm font-bold text-[#3f9d6c] tabular-nums w-16 text-right">
                          {expense.amount}
                        </span>
                      </div>
                    <% end %>
                    <div class="h-12 bg-transparent"></div>
                  </div>
                  <%!-- Notebook edit panel --%>
                  <%= if @selected_expense do %>
                    <div id="notebook-expense-edit-panel" class="absolute inset-0 flex">
                      <%!-- Dim overlay --%>
                      <div class="flex-1 bg-[#0d1a35]/50" phx-click="close_expense"></div>
                      <%!-- Denim cover panel --%>
                      <div class="nb-denim w-80 border-l border-[#0d1a35] flex flex-col shadow-2xl">
                        <div class="flex items-start justify-between px-6 pt-5 pb-2">
                          <div>
                            <p class="font-caveat text-2xl text-white font-semibold leading-tight">
                              Edit Expense
                            </p>
                            <p class="font-nunito text-xs text-[#6ca0ea] mt-0.5">June · Groceries</p>
                          </div>
                          <button
                            phx-click="close_expense"
                            class="text-[#6ca0ea] hover:text-white transition-colors mt-0.5"
                          >
                            <.icon name="hero-x-mark" class="w-6 h-6" />
                          </button>
                        </div>
                        <div class="px-5 pb-4 flex-1 space-y-3 overflow-y-auto">
                          <div class="bg-white/10 rounded-lg px-4 py-3">
                            <label class="font-nunito text-xs font-semibold text-[#6ca0ea] uppercase tracking-wide block mb-1">
                              Date
                            </label>
                            <input
                              type="date"
                              value={to_date_input(@selected_expense.date)}
                              class="font-nunito w-full text-sm bg-transparent border-b border-[#6ca0ea]/50 text-white focus:outline-none focus:border-[#6ca0ea] pb-1 transition-colors"
                            />
                          </div>
                          <div class="bg-white/10 rounded-lg px-4 py-3">
                            <label class="font-nunito text-xs font-semibold text-[#6ca0ea] uppercase tracking-wide block mb-1">
                              Description
                            </label>
                            <input
                              type="text"
                              value={@selected_expense.description}
                              class="font-nunito w-full text-sm bg-transparent border-b border-[#6ca0ea]/50 text-white focus:outline-none focus:border-[#6ca0ea] pb-1 transition-colors"
                            />
                          </div>
                          <div class="bg-white/10 rounded-lg px-4 py-3">
                            <label class="font-nunito text-xs font-semibold text-[#6ca0ea] uppercase tracking-wide block mb-1">
                              Cost
                            </label>
                            <input
                              type="text"
                              value={@selected_expense.amount}
                              class="font-nunito w-full text-sm bg-transparent border-b border-[#6ca0ea]/50 text-white focus:outline-none focus:border-[#6ca0ea] pb-1 transition-colors"
                            />
                          </div>
                          <div>
                            <label class="font-nunito text-xs font-semibold text-[#6ca0ea] uppercase tracking-wide block mb-2 px-1">
                              Tags
                            </label>
                            <div class="space-y-1.5">
                              <%= for tag <- @available_tags do %>
                                <label class="flex items-center gap-2.5 cursor-pointer bg-white/10 hover:bg-white/20 rounded-lg px-3 py-2 transition-colors">
                                  <input
                                    type="checkbox"
                                    checked={
                                      Enum.any?(@selected_expense.tags, &(&1.label == tag.label))
                                    }
                                    class="w-4 h-4 rounded border-white/30 bg-white/10 text-[#3f7fd6] focus:ring-[#3f7fd6] focus:ring-offset-0"
                                  />
                                  <span
                                    class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                                    style={"background: #{nb_tag_swatch(tag.label)}"}
                                  >
                                  </span>
                                  <span class="font-nunito text-sm text-[#c3d2f0]">{tag.label}</span>
                                </label>
                              <% end %>
                            </div>
                          </div>
                        </div>
                        <div class="flex items-center justify-between px-6 py-4 border-t border-white/10">
                          <button class="font-nunito text-sm font-bold text-[#e0796e] hover:text-[#f0958b] transition-colors">
                            Delete
                          </button>
                          <button class="font-nunito font-bold px-5 py-2 text-sm text-white bg-[#3f9d6c] hover:bg-[#34875b] rounded-full transition-colors shadow-sm">
                            Save
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <%!-- Button Design Lab — B5 Press Variations --%>
              <div class="bg-white/70 rounded-xl border border-[#c3d2f0] p-6 shadow-sm">
                <p class="font-nunito text-[10px] font-bold uppercase tracking-widest text-[#6980b0] mb-5">Press Button · Color Variations</p>
                <div class="grid grid-cols-3 gap-x-6 gap-y-7">

                  <%!-- P1 — Classic (reference) --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P1 · Classic <span class="font-normal text-[#6980b0]">reference</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press" style="--sh: #1b3a9a; background: #1e40af; border: 2px solid #1e40af">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Fill, border, and shadow all drawn from one sapphire tint. The reference point.</p>
                  </div>

                  <%!-- P2 — Emerald Ring --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P2 · Emerald Ring <span class="font-normal text-[#6980b0]">border contrast</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press" style="--sh: #1b3a9a; background: #1e40af; border: 2px solid #059669">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #059669; color: #059669">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #059669; color: #059669; background: color-mix(in srgb, #059669 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Sapphire fill, emerald border, dark sapphire shadow. The ring reads as a distinct accent layer from a separate hue family.</p>
                  </div>

                  <%!-- P3 — Lifted Fill --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P3 · Lifted Fill <span class="font-normal text-[#6980b0]">fill contrast</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press" style="--sh: #1b3a9a; background: #3060d8; border: 2px solid #1e40af">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Fill is one step lighter than classic; border and shadow stay classic. The darker frame visibly wraps the lighter fill.</p>
                  </div>

                  <%!-- P4 — Amber Shadow --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P4 · Amber Shadow <span class="font-normal text-[#6980b0]">shadow contrast</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press" style="--sh: #b45309; background: #1e40af; border: 2px solid #1e40af">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #b45309; border: 2px solid #1e40af; color: #1e40af">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #b45309; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Border matches fill but the offset shadow shifts to amber. The button reads cool; the depth cue reads warm — a subtle surprise on press.</p>
                  </div>

                  <%!-- P5 — Full Split --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P5 · Full Split <span class="font-normal text-[#6980b0]">fill / border / shadow</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press" style="--sh: #c2410c; background: #1e40af; border: 2px solid #059669">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #c2410c; border: 2px solid #059669; color: #059669">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #c2410c; border: 2px solid #059669; color: #059669; background: color-mix(in srgb, #059669 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Sapphire fill · emerald border · orange-red shadow. Every visual layer speaks a different hue — loud but compositionally rich.</p>
                  </div>

                  <%!-- P6 — Ivory Press --%>
                  <div class="space-y-2.5">
                    <p class="font-nunito text-xs font-bold text-[#22335c]">P6 · Ivory Press <span class="font-normal text-[#6980b0]">light fill</span></p>
                    <div class="flex items-center gap-2">
                      <button class="font-nunito font-bold px-4 py-1.5 text-sm rounded nb-stamp-press" style="--sh: #059669; background: #f5f2e8; color: #1e2d4d; border: 2px solid #1e40af">New Expense</button>
                      <button class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press" style="--sh: #059669; border: 2px solid #1e40af; color: #1e40af">Open</button>
                      <button class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press" style="--sh: #059669; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)">?</button>
                    </div>
                    <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">Warm ivory fill, sapphire border, emerald shadow. Feels like a rubber stamp pressed onto notepaper — the green undercut reads as ink pooling.</p>
                  </div>

                </div>
              </div>
              </div>
              <%!-- /nb-tint wrapper --%>
            <% true -> %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
