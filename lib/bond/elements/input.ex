defmodule Bond.Elements.Input do
  @moduledoc "A notebook-themed text input element."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :type, :string, default: "text", doc: "HTML input type; only text supported for now"
  attr :class, :string, default: nil, doc: "Additional classes appended to the base input classes"
  attr :rest, :global, doc: "HTML attributes (id, placeholder, value, phx-*, etc.)"

  @spec input(Socket.assigns()) :: Rendered.t()
  def input(assigns) do
    ~H"""
    <input
      type={@type}
      class={[
        "bond-input font-nunito px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none",
        @class
      ]}
      style={"color: #{Bond.Tokens.color(:content)}; border-color: #{Bond.Tokens.color(:accent)}; background: #{Bond.Tokens.color(:surface)}; --bond-placeholder: #{Bond.Tokens.color(:content_placeholder)}"}
      {@rest}
    />
    """
  end
end
