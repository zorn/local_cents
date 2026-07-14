defmodule LocalCentsWeb.Bond.Elements.Button do
  @moduledoc """
  A button with primary, outline, square, and danger variants.

  `:primary`, `:outline`, and `:square` are stamp-press buttons. `:danger` is a
  borderless red **text** button for a destructive secondary action (e.g. Delete)
  that should read as subordinate to the primary action beside it; it is tuned for
  dark panel backgrounds (`Bond.Layouts.SidePanel`), matching `variant="frosted"`
  inputs.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :variant, :atom,
    default: :primary,
    values: [:primary, :outline, :square, :danger],
    doc: """
    Visual style — :primary (filled blue), :outline (bordered), :square (small
    fixed-size square), :danger (borderless red text for a destructive action)
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

  # `disabled:` utilities dim the button and block the pointer; the stamp-press
  # hover/active is suppressed for `:disabled` in bond.css so a disabled button
  # also stops reacting to hover.
  @disabled "disabled:opacity-40 disabled:cursor-not-allowed"

  defp button_class(:primary),
    do: "font-bold px-4 py-1.5 text-sm text-white rounded bond-stamp #{@disabled}"

  defp button_class(:outline),
    do: "font-bold px-3 py-1.5 text-sm rounded bond-stamp #{@disabled}"

  defp button_class(:square),
    do:
      "font-bold text-sm rounded bond-stamp w-7 h-7 flex items-center justify-center #{@disabled}"

  # No stamp/border/background — a plain red text button that yields to the
  # primary action beside it. error-400/300 read on the dark side-panel bg.
  defp button_class(:danger),
    do: "font-bold text-sm text-error-400 hover:text-error-300 transition-colors #{@disabled}"

  defp button_style(:primary),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); background: var(--color-primary-800); border: 2px solid var(--color-primary-800)"

  defp button_style(:outline),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); color: var(--color-primary-800); border: 2px solid var(--color-primary-800); background: transparent"

  defp button_style(:square),
    do:
      "--bond-stamp-shadow: var(--color-surface-900); color: var(--color-primary-800); border: 2px solid var(--color-primary-800); background: color-mix(in srgb, var(--color-primary-800) 12%, transparent)"

  # The danger variant is styled entirely by its Tailwind classes.
  defp button_style(:danger), do: nil
end
