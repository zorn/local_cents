defmodule Bond.Layouts.DesktopWindow do
  @moduledoc """
  A component that mimics the look and feel of a desktop window.

  This is primarily uses within the Storybook when presenting sample UI.
  """

  use Phoenix.Component

  slot :inner_block, required: true

  @spec desktop_window(map()) :: Phoenix.LiveView.Rendered.t()
  def desktop_window(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-lg border border-gray-300">
      <div class="flex items-center space-x-2 px-4 py-2 bg-gray-100 rounded-tl-lg rounded-tr-lg">
        <div class="w-3 h-3 bg-red-500 rounded-full"></div>
        <div class="w-3 h-3 bg-yellow-500 rounded-full"></div>
        <div class="w-3 h-3 bg-green-500 rounded-full"></div>
      </div>
      <div class="p-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
