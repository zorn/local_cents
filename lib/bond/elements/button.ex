defmodule Bond.Elements.Button do
  @moduledoc "A primitive button element."

  use Phoenix.Component

  attr :rest, :global

  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    ~H"""
    <button class="bg-emerald-400" {@rest}>
      zorn {render_slot(@inner_block)}
    </button>
    """
  end
end
