defmodule Bond.Elements.Input do
  @moduledoc "A primitive text input element."

  use Phoenix.Component

  attr :rest, :global
  attr :value, :string, default: ""
  attr :placeholder, :string, default: nil

  @spec input(map()) :: Phoenix.LiveView.Rendered.t()
  def input(assigns) do
    ~H"""
    <input type="text" value={@value} placeholder={@placeholder} {@rest} class="" />
    """
  end
end
