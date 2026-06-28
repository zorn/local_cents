defmodule Bond.Layouts.InputBar do
  @moduledoc "A tinted bar layout with a leading region and a trailing region, arranged side by side."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  slot :leading_content, required: true, doc: "The primary region, grows to fill available space"
  slot :trailing_content, required: true, doc: "The action region, sized to its content"

  @spec input_bar(Socket.assigns()) :: Rendered.t()
  def input_bar(assigns) do
    ~H"""
    <div
      class="mx-4 rounded-lg px-3 py-2.5 nb-t-bg-soft"
      style={"border: 1px solid #{Bond.Tokens.color(:border)}; box-shadow: 0 4px 6px -1px #{Bond.Tokens.color(:accent)}33; --nb-t: #{Bond.Tokens.color(:accent)}"}
    >
      <div class="flex items-end gap-2">
        {render_slot(@leading_content)}
        {render_slot(@trailing_content)}
      </div>
    </div>
    """
  end
end
