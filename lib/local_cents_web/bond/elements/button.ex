defmodule LocalCentsWeb.Bond.Elements.Button do
  @moduledoc "A stamp-press button with primary, outline, and square variants."

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :variant, :atom,
    default: :primary,
    values: [:primary, :outline, :square],
    doc: """
    Visual style — :primary (filled blue), :outline (bordered), :square (small fixed-size square)
    """

  attr :rest, :global, doc: "HTML attributes passed through to the button element"

  slot :inner_block, required: true, doc: "Button label or character"

  @spec button(Socket.assigns()) :: Rendered.t()
  def button(assigns) do
    ~H"""
    <button class={button_class(@variant)} style={button_style(@variant)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_class(:primary),
    do: "font-nunito font-bold px-4 py-1.5 text-sm text-white rounded nb-stamp-press"

  defp button_class(:outline),
    do: "font-nunito font-bold px-3 py-1 text-sm rounded nb-stamp-press"

  defp button_class(:square),
    do:
      "font-nunito font-bold text-sm rounded nb-stamp-press w-7 h-7 flex items-center justify-center"

  defp button_style(:primary) do
    a = Bond.Tokens.color(:accent)
    s = Bond.Tokens.color(:button_shadow)
    "--sh: #{s}; background: #{a}; border: 2px solid #{a}"
  end

  defp button_style(:outline) do
    a = Bond.Tokens.color(:accent)
    s = Bond.Tokens.color(:button_shadow)
    "--sh: #{s}; color: #{a}; border: 2px solid #{a}; background: transparent"
  end

  defp button_style(:square) do
    a = Bond.Tokens.color(:accent)
    s = Bond.Tokens.color(:button_shadow)

    "--sh: #{s}; color: #{a}; border: 2px solid #{a}; background: color-mix(in srgb, #{a} 12%, transparent)"
  end
end
