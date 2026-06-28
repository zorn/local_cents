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
        "font-nunito px-3 py-1.5 text-sm border-b-2 nb-t-border bg-white focus:outline-none text-[#22335c] placeholder-[#a0b4d0] rounded-sm transition-shadow focus:[box-shadow:0_0_0_4px_rgba(30,64,175,0.12)]",
        @class
      ]}
      {@rest}
    />
    """
  end
end
