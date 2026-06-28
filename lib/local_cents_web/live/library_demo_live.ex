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
      },
      %{
        id: 4,
        date: "05/25/2026",
        description: "Target run — school supplies",
        tags: [
          %{label: "kids", class: "bg-sky-100 text-sky-700 border border-sky-200"}
        ],
        amount: "$43.18"
      },
      %{
        id: 5,
        date: "05/22/2026",
        description: "Trader Joe's",
        tags: [
          %{label: "groceries", class: "bg-purple-100 text-purple-700 border border-purple-200"},
          %{label: "food", class: "bg-orange-100 text-orange-700 border border-orange-200"}
        ],
        amount: "$89.76"
      },
      %{
        id: 6,
        date: "05/20/2026",
        description: "Chipotle lunch",
        tags: [
          %{label: "dining", class: "bg-green-100 text-green-700 border border-green-200"},
          %{label: "food", class: "bg-orange-100 text-orange-700 border border-orange-200"}
        ],
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
        tags: [
          %{label: "kids", class: "bg-sky-100 text-sky-700 border border-sky-200"},
          %{label: "sports", class: "bg-red-100 text-red-700 border border-red-200"}
        ],
        amount: "$54.99"
      },
      %{
        id: 9,
        date: "05/12/2026",
        description: "Costco run",
        tags: [
          %{label: "groceries", class: "bg-purple-100 text-purple-700 border border-purple-200"}
        ],
        amount: "$213.55"
      },
      %{
        id: 10,
        date: "05/10/2026",
        description: "Pizza night",
        tags: [
          %{label: "dining", class: "bg-green-100 text-green-700 border border-green-200"}
        ],
        amount: "$38.00"
      }
    ]

    {:ok,
     assign(socket,
       books: books,
       available_tags: available_tags,
       expenses: expenses,
       show_new_expense: false,
       selected_expense: nil,
       active_style: "simple"
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    style = Map.get(params, "style", socket.assigns.active_style)

    valid_styles = ["simple", "warm", "dark", "notebook"]
    style = Enum.find(valid_styles, "simple", &(&1 == style))

    selected_expense =
      case Map.get(params, "expense_id") do
        nil -> nil
        id -> Enum.find(socket.assigns.expenses, &(&1.id == String.to_integer(id)))
      end

    {:noreply,
     assign(socket,
       active_style: style,
       show_new_expense: false,
       selected_expense: selected_expense
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("switch_style", %{"style" => style}, socket) do
    {:noreply, push_patch(socket, to: ~p"/library-demo?style=#{style}")}
  end

  def handle_event("select_expense", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/library-demo?style=#{socket.assigns.active_style}&expense_id=#{id}"
     )}
  end

  def handle_event("close_expense", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/library-demo?style=#{socket.assigns.active_style}")}
  end

  defp to_date_input(date) do
    case String.split(date, "/") do
      [m, d, y] -> "#{y}-#{m}-#{d}"
      _ -> date
    end
  end

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

  defp graph_paper_chart_placeholder(assigns) do
    ~H"""
    <div class="mx-4 mt-4 mb-3 nb-graph rounded-lg border border-[#c3d2f0] shadow-md shadow-[#3f7fd6]/20 px-6 py-5">
      <div class="flex items-end gap-2 h-24">
        <div class="flex-1 nb-t-bar rounded-t-sm opacity-90" style="height: 75%"></div>
        <div class="flex-1 nb-t-bar rounded-t-sm opacity-60" style="height: 41%"></div>
        <div class="flex-1 nb-t-bar rounded-t-sm opacity-75" style="height: 58%"></div>
        <div class="flex-1 nb-t-bar rounded-t-sm opacity-50" style="height: 21%"></div>
        <div class="flex-1 nb-t-bar rounded-t-sm opacity-65" style="height: 33%"></div>
      </div>
    </div>
    """
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
              <LocalCentsWeb.LibraryDemoComponents.simple_style
                books={@books}
                expenses={@expenses}
                available_tags={@available_tags}
                show_new_expense={@show_new_expense}
                selected_expense={@selected_expense}
              />
              <%!-- ════════════════════════════════════════════ WARM LEDGER STYLE ═══ --%>
            <% @active_style == "warm" -> %>
              <LocalCentsWeb.LibraryDemoComponents.warm_style
                books={@books}
                expenses={@expenses}
                available_tags={@available_tags}
                show_new_expense={@show_new_expense}
                selected_expense={@selected_expense}
              />
              <%!-- ═══════════════════════════════════════════════ DARK SLATE STYLE ═══ --%>
            <% @active_style == "dark" -> %>
              <LocalCentsWeb.LibraryDemoComponents.dark_style
                books={@books}
                expenses={@expenses}
                available_tags={@available_tags}
                show_new_expense={@show_new_expense}
                selected_expense={@selected_expense}
              />
              <%!-- ══════════════════════════════════════════════ NOTEBOOK STYLE ═══ --%>
            <% @active_style == "notebook" -> %>
              <div class="space-y-6">
                <%!-- Notebook Library Window --%>
                <Bond.desktop_window title="Library">
                  <%!-- Ruled paper book list --%>
                  <Bond.list_view max_height="320px">
                    <%= for book <- @books do %>
                      <Bond.book_cell
                        name={book.name}
                        last_updated={book.last_updated}
                      />
                    <% end %>
                  </Bond.list_view>
                  <%!-- Footer --%>
                  <div class="flex items-center justify-between px-4 py-4">
                    <Bond.button>New Book</Bond.button>
                    <Bond.button variant={:square}>?</Bond.button>
                  </div>
                </Bond.desktop_window>

                <%!-- Notebook Document Window --%>
                <Bond.desktop_window title="Family Expenses">
                  <%!-- Content area (edit panel is relative to this, not the title bar) --%>
                  <div class="relative overflow-hidden">
                    <.graph_paper_chart_placeholder />
                    <%!-- New Expense row --%>
                    <Bond.input_bar>
                      <:leading_content>
                        <Bond.input
                          id="notebook-new-expense-input"
                          placeholder="coffee 4.75 or netflix 22.99 yesterday"
                          class="flex-1"
                        />
                      </:leading_content>
                      <:trailing_content>
                        <Bond.button id="notebook-new-expense-create-btn">
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
                              id="notebook-expense-search-input"
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
                      <%!-- FIXME: In the future we should be able to pass in the tags directly without the mapping. --%>
                      <%= for expense <- @expenses do %>
                        <Bond.expense_cell
                          id={"notebook-expense-row-#{expense.id}"}
                          date={expense.date}
                          description={expense.description}
                          amount={expense.amount}
                          tags={
                            Enum.map(
                              expense.tags,
                              &%{label: &1.label, color: nb_tag_swatch(&1.label)}
                            )
                          }
                          phx-click="select_expense"
                          phx-value-id={expense.id}
                        />
                      <% end %>
                    </Bond.list_view>
                    <%!-- Notebook edit panel --%>
                    <%= if @selected_expense do %>
                      <Bond.side_panel
                        id="notebook-expense-edit-panel"
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
                            <label class="font-nunito text-xs font-semibold text-[#6ca0ea] uppercase tracking-wide block mb-2 px-1">
                              Tags
                            </label>
                            <div class="space-y-1.5">
                              <%= for tag <- @available_tags do %>
                                <Bond.checkbox
                                  variant="pill_row"
                                  checked={
                                    Enum.any?(@selected_expense.tags, &(&1.label == tag.label))
                                  }
                                >
                                  <span
                                    class="w-2.5 h-2.5 rounded-full shrink-0"
                                    style={"background: #{nb_tag_swatch(tag.label)}"}
                                  />
                                  <span class="font-nunito text-sm text-[#c3d2f0]">
                                    {tag.label}
                                  </span>
                                </Bond.checkbox>
                              <% end %>
                            </div>
                          </div>
                        </div>
                        <:footer>
                          <button class="font-nunito text-sm font-bold text-[#e0796e] hover:text-[#f0958b] transition-colors">
                            Delete
                          </button>
                          <Bond.button>Save</Bond.button>
                        </:footer>
                      </Bond.side_panel>
                    <% end %>
                  </div>
                </Bond.desktop_window>
                <%!-- Button Design Lab — B5 Press Variations --%>
                <div class="bg-white/70 rounded-xl border border-[#c3d2f0] p-6 shadow-sm">
                  <p class="font-nunito text-[10px] font-bold uppercase tracking-widest text-[#6980b0] mb-5">
                    Press Button · Color Variations
                  </p>
                  <div class="grid grid-cols-3 gap-x-6 gap-y-7">
                    <%!-- P1 — Classic (reference) --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P1 · Classic <span class="font-normal text-[#6980b0]">reference</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"
                          style="--sh: #1b3a9a; background: #1e40af; border: 2px solid #1e40af"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #1b3a9a; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Fill, border, and shadow all drawn from one sapphire tint. The reference point.
                      </p>
                    </div>

                    <%!-- P2 — Emerald Ring --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P2 · Emerald Ring
                        <span class="font-normal text-[#6980b0]">border contrast</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"
                          style="--sh: #1b3a9a; background: #1e40af; border: 2px solid #059669"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #1b3a9a; border: 2px solid #059669; color: #059669"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #1b3a9a; border: 2px solid #059669; color: #059669; background: color-mix(in srgb, #059669 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Sapphire fill, emerald border, dark sapphire shadow. The ring reads as a distinct accent layer from a separate hue family.
                      </p>
                    </div>

                    <%!-- P3 — Lifted Fill --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P3 · Lifted Fill <span class="font-normal text-[#6980b0]">fill contrast</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"
                          style="--sh: #1e293b; background: #3060d8; border: 2px solid #1e40af"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #1e293b; border: 2px solid #1e40af; color: #1e40af"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #1e293b; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Fill is one step lighter than classic; border and shadow stay classic. The darker frame visibly wraps the lighter fill.
                      </p>
                    </div>

                    <%!-- P4 — Amber Shadow --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P4 · Amber Shadow
                        <span class="font-normal text-[#6980b0]">shadow contrast</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"
                          style="--sh: #b45309; background: #1e40af; border: 2px solid #1e40af"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #b45309; border: 2px solid #1e40af; color: #1e40af"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #b45309; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Border matches fill but the offset shadow shifts to amber. The button reads cool; the depth cue reads warm — a subtle surprise on press.
                      </p>
                    </div>

                    <%!-- P5 — Full Split --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P5 · Full Split
                        <span class="font-normal text-[#6980b0]">fill / border / shadow</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"
                          style="--sh: #c2410c; background: #1e40af; border: 2px solid #059669"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #c2410c; border: 2px solid #059669; color: #059669"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #c2410c; border: 2px solid #059669; color: #059669; background: color-mix(in srgb, #059669 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Sapphire fill · emerald border · orange-red shadow. Every visual layer speaks a different hue — loud but compositionally rich.
                      </p>
                    </div>

                    <%!-- P6 — Ivory Press --%>
                    <div class="space-y-2.5">
                      <p class="font-nunito text-xs font-bold text-[#22335c]">
                        P6 · Ivory Press <span class="font-normal text-[#6980b0]">light fill</span>
                      </p>
                      <div class="flex items-center gap-2">
                        <button
                          class="font-nunito font-bold px-4 py-1.5 text-sm rounded nb-stamp-press"
                          style="--sh: #059669; background: #f5f2e8; color: #1e2d4d; border: 2px solid #1e40af"
                        >
                          New Expense
                        </button>
                        <button
                          class="font-nunito font-bold text-sm rounded px-3 py-1 nb-stamp-press"
                          style="--sh: #059669; border: 2px solid #1e40af; color: #1e40af"
                        >
                          Open
                        </button>
                        <button
                          class="font-nunito w-7 h-7 rounded text-sm font-bold flex items-center justify-center nb-stamp-press"
                          style="--sh: #059669; border: 2px solid #1e40af; color: #1e40af; background: color-mix(in srgb, #1e40af 12%, transparent)"
                        >
                          ?
                        </button>
                      </div>
                      <p class="font-nunito text-[10px] text-[#6980b0] leading-snug">
                        Warm ivory fill, sapphire border, emerald shadow. Feels like a rubber stamp pressed onto notepaper — the green undercut reads as ink pooling.
                      </p>
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
