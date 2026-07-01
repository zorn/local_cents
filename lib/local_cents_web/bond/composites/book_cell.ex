defmodule LocalCentsWeb.Bond.Composites.BookCell do
  @moduledoc "A notebook-themed book row for use inside Bond.Elements.ListView."

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :name, :string, required: true, doc: "Book title displayed as the primary text"

  attr :last_updated, :string,
    required: true,
    doc: "Subtitle showing when the book was last updated"

  attr :rest, :global, doc: "HTML attributes passed through to the row element (e.g. phx-click)"

  @spec book_cell(Socket.assigns()) :: Rendered.t()
  def book_cell(assigns) do
    ~H"""
    <div
      class="flex items-center gap-4 px-4 py-4 nb-t-hover-row transition-colors"
      style={"--nb-t: #{Bond.Tokens.color(:accent)}"}
      {@rest}
    >
      <div class="flex-1 min-w-0">
        <p
          class="font-nunito text-base font-semibold leading-snug"
          style={"color: #{Bond.Tokens.color(:content)}"}
        >
          {@name}
        </p>
        <p
          class="font-nunito text-xs mt-0.5"
          style={"color: #{Bond.Tokens.color(:content_secondary)}"}
        >
          Last Updated: {@last_updated}
        </p>
      </div>
      <Bond.Elements.Button.button variant={:outline}>Open</Bond.Elements.Button.button>
    </div>
    """
  end
end
