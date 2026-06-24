defmodule Bond.Elements.Button do
  use Phoenix.Component

  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button class="bg-emerald-400" {@rest}>
      zorn {render_slot(@inner_block)}
    </button>
    """
  end
end
