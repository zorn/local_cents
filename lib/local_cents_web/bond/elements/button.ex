defmodule LocalCentsWeb.Bond.Elements.Button do
  @moduledoc "A stamp-press button with primary, outline, and square variants."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :variant, :atom,
    default: :primary,
    values: [:primary, :outline, :square],
    doc: """
    Visual style — :primary (filled blue), :outline (bordered), :square (small fixed-size square)
    """

  attr :type, :string,
    default: "button",
    doc:
      ~s(The button's `type` attribute; defaults to "button" so it never accidentally submits a form)

  attr :rest, :global, doc: "HTML attributes passed through to the button element"

  slot :inner_block, required: true, doc: "Button label or character"

  @spec button(Socket.assigns()) :: Rendered.t()
  def button(assigns) do
    ~H"""
    <button type={@type} class={button_class(@variant)} style={button_style(@variant)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_class(:primary),
    do: "font-bold px-4 py-1.5 text-sm text-white rounded bond-stamp"

  defp button_class(:outline),
    do: "font-bold px-3 py-1 text-sm rounded bond-stamp"

  defp button_class(:square),
    do: "font-bold text-sm rounded bond-stamp w-7 h-7 flex items-center justify-center"

  defp button_style(:primary),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); background: var(--color-primary-800); border: 2px solid var(--color-primary-800)"

  defp button_style(:outline),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); color: var(--color-primary-800); border: 2px solid var(--color-primary-800); background: transparent"

  defp button_style(:square),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); color: var(--color-primary-800); border: 2px solid var(--color-primary-800); background: color-mix(in srgb, var(--color-primary-800) 12%, transparent)"
end
