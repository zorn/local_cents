defmodule Storybook.Demos.LibraryWindow do
  use LocalCentsWeb.Storybook.Story, :example

  def doc,
    do:
      "The Library window — a desktop window listing expense books, composed entirely from Bond components."

  @books [
    %{id: 1, name: "Family Expenses", last_updated: "06-02-2026 1:34 PM"},
    %{id: 2, name: "Side Hustle LLC Expenses", last_updated: "06-02-2026 1:34 PM"}
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :books, @books)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="font-sans">
      <p class="text-xs text-surface-500 mb-2">
        Drag the bottom-right corner to resize the window and watch the elements reflow.
      </p>
      <div class="resize-x overflow-hidden min-w-[320px] max-w-full w-[576px] p-6">
        <Bond.desktop_window title="Library">
          <Bond.list_view max_height="320px">
            <Bond.book_cell
              :for={book <- @books}
              name={book.name}
              last_updated={book.last_updated}
            />
          </Bond.list_view>
          <div class="flex items-center justify-between px-4 py-4">
            <Bond.button>New Book</Bond.button>
            <Bond.button variant={:square}>?</Bond.button>
          </div>
        </Bond.desktop_window>
      </div>
    </div>
    """
  end
end
