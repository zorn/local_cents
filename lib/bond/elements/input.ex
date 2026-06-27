defmodule Bond.Elements.Input do
  @moduledoc "A primitive text input element."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :rest, :global
  attr :value, :string, default: ""
  attr :placeholder, :string, default: nil

  @spec input(Socket.assigns()) :: Rendered.t()
  def input(assigns) do
    ~H"""
    <input type="text" value={@value} placeholder={@placeholder} {@rest} class="" />
    """
  end
end
