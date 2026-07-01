defmodule LocalCentsWeb.Bond.Elements.TagPill do
  @moduledoc "A small pill displaying a colored dot swatch and a text label."

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :label, :string, required: true, doc: "The tag label text"
  attr :color, :string, required: true, doc: "Hex color for the dot swatch"

  @spec tag_pill(Socket.assigns()) :: Rendered.t()
  def tag_pill(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold"
      style={"background: #{Bond.Tokens.color(:surface)}; border: 1px solid #{Bond.Tokens.color(:border_subtle)}; color: #{Bond.Tokens.color(:content)}"}
    >
      <span class="w-2 h-2 rounded-full shrink-0" style={"background: #{@color}"}></span>
      {@label}
    </span>
    """
  end
end
