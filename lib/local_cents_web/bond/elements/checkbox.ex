defmodule LocalCentsWeb.Bond.Elements.Checkbox do
  @moduledoc """
  A checkbox element for forms.

  Renders a `<label>` wrapping a native `<input type="checkbox">` followed by
  the `inner_block` slot. Because the outer element is a `<label>`, clicking
  anywhere in the row (including the slot content) toggles the checkbox without
  needing a separate `for` attribute.

  ## Slot-based label content

  Unlike a plain string `label` attr, the `inner_block` slot accepts any markup
  — plain text, colored swatch dots, icons, or combinations thereof. The
  component itself knows nothing about what goes inside; that is the caller's
  responsibility.

  ## Variants

  - **`"default"`** — a minimal flex row with no background. Suitable for
    standard light-background forms.
  - **`"pill_row"`** — the row gains a frosted semi-transparent background,
    rounded corners, and a hover highlight. Designed for use inside dark panels
    such as `Bond.Layouts.SidePanel`.

  ## Examples

      <%!-- Plain text label --%>
      <Bond.checkbox name="agree" checked={@agreed}>
        I agree to the terms
      </Bond.checkbox>

      <%!-- Rich content with a colored swatch (pill_row variant) --%>
      <Bond.checkbox variant="pill_row" name="tags[]" value={tag.label}
                     checked={tag.label in @selected_tags}>
        <span class="w-2.5 h-2.5 rounded-full shrink-0" style={"background: \#{tag.color}"} />
        <span class="text-sm">{tag.label}</span>
      </Bond.checkbox>
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :checked, :boolean, default: false, doc: "Whether the checkbox is checked"

  attr :id, :any, default: nil, doc: "DOM id for the input element"
  attr :name, :any, default: nil, doc: "Input name attribute"
  attr :value, :any, default: nil, doc: "Input value submitted with the form"

  attr :variant, :string,
    default: "default",
    doc: ~s("default" — plain flex row; "pill_row" — frosted pill with background and hover)

  attr :rest, :global,
    doc: "HTML attributes passed to the <input> element (phx-click, disabled, etc.)"

  slot :inner_block,
    required: true,
    doc: "Content rendered beside the checkbox — text, swatches, icons, or any markup"

  @spec checkbox(Socket.assigns()) :: Rendered.t()
  def checkbox(assigns) do
    ~H"""
    <label class={wrapper_class(@variant)}>
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class={input_class(@variant)}
        {@rest}
      />
      {render_slot(@inner_block)}
    </label>
    """
  end

  defp input_class("pill_row"),
    do:
      "w-4 h-4 rounded border-white/30 bg-white/10 text-[#3f7fd6] focus:ring-[#3f7fd6] focus:ring-offset-0"

  defp input_class(_),
    do: "w-4 h-4 rounded"

  defp wrapper_class("pill_row"),
    do:
      "flex items-center gap-2.5 cursor-pointer bg-white/10 hover:bg-white/20 rounded-lg px-3 py-2 transition-colors"

  defp wrapper_class(_),
    do: "flex items-center gap-2.5 cursor-pointer"
end
