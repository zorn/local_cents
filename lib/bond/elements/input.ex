defmodule Bond.Elements.Input do
  use Phoenix.Component

  attr :rest, :global
  attr :value, :string, default: ""
  attr :placeholder, :string, default: nil

  def input(assigns) do
    ~H"""
    <input type="text" value={@value} placeholder={@placeholder} {@rest} class="" />
    """
  end
end
