defmodule Bond.Layouts.ListControls do
  @moduledoc "A styled horizontal strip for list search, filtering, and sorting controls."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  slot :leading_content, required: true, doc: "The primary region, grows to fill available space"
  slot :trailing_content, required: true, doc: "The action region, sized to its content"

  @spec list_controls(Socket.assigns()) :: Rendered.t()
  def list_controls(assigns) do
    ~H"""
    <div
      class="px-3 py-2.5 border-b nb-t-bg-soft"
      style={"--nb-t: #{Bond.Tokens.color(:accent)}; border-color: #{Bond.Tokens.color(:border_subtle)}"}
    >
      <div class="flex items-center gap-2">
        {render_slot(@leading_content)}
        {render_slot(@trailing_content)}
      </div>
    </div>
    """
  end
end
