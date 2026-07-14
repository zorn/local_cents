defmodule LocalCentsWeb.Bond.Elements.Select do
  @moduledoc """
  A Bond select element — a styled native `<select>` for choosing one value from a
  fixed list.

  A native `<select>` is used on purpose: it is keyboard- and screen-reader
  accessible for free and renders the OS-native dropdown, which suits the desktop
  shell. This element only styles the closed control to match `Bond.Elements.Input`;
  the open list is drawn by the OS.

  Like `Bond.Elements.Input`, it renders a self-contained wrapper `<div>` holding an
  optional label, the `<select>`, and any validation errors, and it shares that
  element's `variant`, `label`, `errors`, form-field, and `class` conventions (see
  those docs). Two attrs are specific to the select:

  - **`options`** — the choices, as a list of `{label, value}` tuples (anything
    `Phoenix.HTML.Form.options_for_select/2` accepts). The option whose value equals
    the current value is marked selected.
  - **`include_blank`** — when true (the default), a leading blank `<option value="">`
    is rendered so "no selection" is representable; its text is `prompt` (empty by
    default). This is how the expense editor offers Uncategorized (see
    [ADR 0018](0018-category-assignment-through-the-editor.html)): a blank selection
    casts to `nil`.

  ## Examples

      <%!-- Wired to a form field, frosted, with a blank (Uncategorized) option --%>
      <Bond.select field={@form[:category_id]} label="Category" variant="frosted" options={@options} />

      <%!-- Standalone, no blank option --%>
      <Bond.select label="Sort" options={[{"Newest", "desc"}, {"Oldest", "asc"}]} include_blank={false} />
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :variant, :string,
    default: "default",
    doc: "Visual variant; \"frosted\" suits dark panel backgrounds"

  attr :label, :string,
    default: nil,
    doc: "Label text shown above the select; omit to render no label"

  attr :options, :list,
    default: [],
    doc: "Choices as a list of {label, value} tuples (Phoenix.HTML.Form.options_for_select/2)"

  attr :include_blank, :boolean,
    default: true,
    doc: "Render a leading blank option (value \"\") so \"no selection\" is representable"

  attr :prompt, :string,
    default: nil,
    doc: "Text of the leading blank option; nil (the default) renders it empty"

  attr :errors, :list,
    default: [],
    doc: "List of error message strings shown below the select"

  attr :field, Phoenix.HTML.FormField,
    doc: "A form field struct (@form[:field]); unpacks id, name, value, and errors automatically"

  attr :id, :any,
    default: nil,
    doc: "DOM id for the select element; derived automatically when field is given"

  attr :name, :any,
    default: nil,
    doc: "Select name attribute; derived automatically when field is given"

  attr :value, :any,
    default: nil,
    doc: "Currently selected value; derived automatically when field is given"

  attr :class, :string,
    default: nil,
    doc: "Classes applied to the outer wrapper div — use for layout (flex-1, w-full, etc.)"

  attr :rest, :global, doc: "HTML attributes (phx-*, disabled, etc.)"

  @spec select(Socket.assigns()) :: Rendered.t()
  def select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      case Phoenix.Component.used_input?(field) do
        true -> field.errors
        false -> []
      end

    # Mirror Bond.Elements.Input: prefer an explicit caller value, fall back to the
    # field's only when none was given, so an intentional "" still overrides.
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, override_or_field(assigns.name, field.name))
    |> assign(:value, override_or_field(assigns.value, field.value))
    |> select()
  end

  def select(assigns) do
    ~H"""
    <div class={@class}>
      <label
        :if={@label}
        for={@id}
        class={[
          "text-xs font-semibold uppercase tracking-wide block mb-1",
          label_color_class(@variant)
        ]}
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "bond-input w-full px-3 py-1.5 text-sm rounded-sm transition-shadow focus:outline-none",
          select_class(@variant)
        ]}
        style={select_style(@variant)}
        {@rest}
      >
        <option :if={@include_blank} value="" selected={blank?(@value)}>{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <p
        :for={msg <- @errors}
        class="mt-1 text-xs flex items-center gap-1"
        style={"color: #{error_color(@variant)};"}
      >
        {msg}
      </p>
    </div>
    """
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp select_class("frosted"),
    do: "border-b-2 text-surface-800 border-primary-400 bg-surface-300"

  defp select_class(_variant),
    do: "border-b-2 text-surface-800 border-primary-800 bg-surface-50"

  defp select_style("frosted"),
    do:
      "--bond-focus-ring: 0 0 0 3px color-mix(in srgb, var(--color-primary-400) 35%, transparent)"

  defp select_style(_variant),
    do:
      "--bond-focus-ring: 0 0 0 3px color-mix(in srgb, var(--color-primary-800) 15%, transparent)"

  defp label_color_class("frosted"), do: "text-primary-400"
  defp label_color_class(_), do: "text-surface-600"

  defp error_color("frosted"), do: "var(--color-error-400)"
  defp error_color(_variant), do: "var(--color-error-600)"

  defp override_or_field(nil, from_field), do: from_field
  defp override_or_field(override, _from_field), do: override

  defp translate_error({msg, opts}) do
    case opts[:count] do
      nil -> Gettext.dgettext(LocalCentsWeb.Gettext, "errors", msg, opts)
      count -> Gettext.dngettext(LocalCentsWeb.Gettext, "errors", msg, msg, count, opts)
    end
  end
end
