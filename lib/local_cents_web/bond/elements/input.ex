defmodule LocalCentsWeb.Bond.Elements.Input do
  @moduledoc """
  A Bond input element.

  Always renders an outer `<div>` wrapper containing an optional label, the
  input element itself, and any validation error messages. This means the
  component is self-contained — callers do not need to wrap it in their own
  `<div>` or manually add a `<label>`.

  ## Variants

  The `variant` attr controls the visual style of the input element:

  - **`"default"`** — an underline-only style suited for light backgrounds.
    The bottom border uses the ink accent color.
  - **`"frosted"`** — a semi-transparent frosted-glass style for use inside
    dark panel backgrounds (e.g. `Bond.Layouts.SidePanel`).
  - **`type="search"`** — a pill-shaped field with an inset magnifying glass
    icon. Only works with `variant="default"`; combining search with another
    variant raises `ArgumentError`.

  ## Label

  Pass `label="My Label"` to render a small uppercase label above the input.
  Omit it (the default) to render no label at all — there is no opt-out attr
  needed. Label color is derived from the variant: `primary-400` for frosted,
  `surface-600` for default.

  ## Errors

  Pass `errors={["can't be blank", "is too short"]}` to render one error
  paragraph per message below the input. When no errors are present (the
  default), nothing is rendered in that slot.

  ## Form field integration

  Pass `field={@form[:email]}` to wire the component directly to a Phoenix
  form field. The component unpacks `id`, `name`, and `value` from the field
  struct automatically, and only shows errors once the user has interacted with
  the field (via `Phoenix.Component.used_input?/1`). Raw `{msg, opts}` error
  tuples from the changeset are translated through Gettext before display.

  You can still pass `id`, `name`, and `value` explicitly when not using a
  form field — useful for standalone inputs that are not backed by a changeset.

  ## The `class` attr

  `class` is always applied to the **outer wrapper `<div>`**, not to the
  `<input>` element. This means it participates correctly in the parent's
  layout — passing `class="flex-1"` makes the whole field (label + input +
  errors) grow inside a flex container, and `class="w-full"` constrains the
  wrapper width. The inner `<input>` and search pill always fill their wrapper
  with `w-full` internally.

  ## Examples

      <%!-- Bare input, no label --%>
      <Bond.input placeholder="coffee 4.75" />

      <%!-- With label and explicit value --%>
      <Bond.input label="Description" value={@expense.description} variant="frosted" class="w-full" />

      <%!-- Wired to a Phoenix form field --%>
      <Bond.input field={@form[:email]} label="Email" />

      <%!-- Search filter, no label --%>
      <Bond.input type="search" placeholder="search..." class="flex-1" />
  """

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :type, :string,
    default: "text",
    values:
      ~w(text search email password number tel url date datetime-local month week time color),
    doc: """
    HTML input type for the single-line field. "search" renders a pill field
    with a magnifying glass icon. "checkbox" is intentionally excluded — use
    Bond.Elements.Checkbox instead.
    """

  attr :variant, :string,
    values: ~w(default frosted),
    default: "default",
    doc: "Visual variant; \"frosted\" suits dark panel backgrounds"

  attr :label, :string,
    default: nil,
    doc: "Label text shown above the input; omit to render no label"

  attr :errors, :list,
    default: [],
    doc: "List of error message strings shown below the input"

  attr :field, Phoenix.HTML.FormField,
    doc: "A form field struct (@form[:field]); unpacks id, name, value, and errors automatically"

  attr :id, :any,
    default: nil,
    doc: "DOM id for the input element; derived automatically when field is given"

  attr :name, :any,
    default: nil,
    doc: "Input name attribute; derived automatically when field is given"

  attr :value, :any,
    default: nil,
    doc:
      "Input value — accepts strings, Date, Decimal, or any type normalize_value/2 handles; derived automatically when field is given"

  attr :class, :string,
    default: nil,
    doc: "Classes applied to the outer wrapper div — use for layout (flex-1, w-full, etc.)"

  attr :rest, :global,
    include: ~w(placeholder),
    doc: "HTML attributes (placeholder, phx-*, disabled, etc.)"

  @spec input(Socket.assigns()) :: Rendered.t()
  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      case Phoenix.Component.used_input?(field) do
        true -> field.errors
        false -> []
      end

    # Assign, not assign_new: the nil defaults mean these keys already exist. A
    # nil-check (not `||`) lets an explicit falsy override — e.g. value={false} or
    # a caller-supplied "" — win over the field binding rather than fall through.
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, override_or_field(assigns.name, field.name))
    |> assign(:value, override_or_field(assigns.value, field.value))
    |> input()
  end

  def input(%{type: "checkbox"} = _assigns) do
    raise ArgumentError,
          "Bond.Elements.Input does not support type=\"checkbox\"; use Bond.Elements.Checkbox instead"
  end

  def input(%{type: "search", variant: v} = _assigns) when v != "default" do
    raise ArgumentError,
          "Bond.Elements.Input: variant=#{inspect(v)} is not supported with type=\"search\""
  end

  def input(%{type: "search"} = assigns) do
    ~H"""
    <div class={@class}>
      <.input_label label={@label} id={@id} variant={@variant} />
      <div class="relative w-full">
        <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none text-surface-600">
          <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5" />
        </div>
        <input
          type="search"
          id={@id}
          name={@name}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class="bond-input pl-7 pr-3 py-1.5 text-sm border bond-ink-border rounded-full focus:outline-none w-full transition-shadow bg-surface-50 text-surface-800"
          style="--bond-placeholder: var(--color-surface-400); --bond-focus-ring: 0 0 0 4px color-mix(in srgb, var(--color-primary-800) 12%, transparent)"
          {@rest}
        />
      </div>
      <.input_errors errors={@errors} variant={@variant} />
    </div>
    """
  end

  def input(%{variant: "frosted"} = assigns) do
    ~H"""
    <div class={@class}>
      <.input_label label={@label} id={@id} variant={@variant} />
      <input
        type={@type}
        id={@id}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class="bond-input w-full px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none text-surface-800 border-primary-400 bg-surface-300"
        style="--bond-placeholder: var(--color-surface-400); --bond-focus-ring: 0 0 0 3px color-mix(in srgb, var(--color-primary-400) 35%, transparent)"
        {@rest}
      />
      <.input_errors errors={@errors} variant={@variant} />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@class}>
      <.input_label label={@label} id={@id} variant={@variant} />
      <input
        type={@type}
        id={@id}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class="bond-input w-full px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none text-surface-800 border-primary-800 bg-surface-50"
        style="--bond-placeholder: var(--color-surface-400); --bond-focus-ring: 0 0 0 3px color-mix(in srgb, var(--color-primary-800) 15%, transparent)"
        {@rest}
      />
      <.input_errors errors={@errors} variant={@variant} />
    </div>
    """
  end

  defp input_label(assigns) do
    ~H"""
    <label
      :if={@label}
      for={@id}
      class={["text-xs font-semibold uppercase tracking-wide block mb-1", label_color_class(@variant)]}
    >
      {@label}
    </label>
    """
  end

  defp input_errors(assigns) do
    ~H"""
    <p
      :for={msg <- @errors}
      class="mt-1 text-xs flex items-center gap-1"
      style={"color: #{error_color(@variant)};"}
    >
      {msg}
    </p>
    """
  end

  # Errors read on the input's own background: a light red on the dark frosted
  # panel, a darker red on the light default/search fields so it keeps contrast.
  defp error_color("frosted"), do: "var(--color-error-400)"
  defp error_color(_variant), do: "var(--color-error-600)"

  defp label_color_class("frosted"), do: "text-primary-400"
  defp label_color_class(_), do: "text-surface-600"

  # Prefer an explicit caller value; fall back to the field's only when none was
  # given (nil), so an intentional falsy value (false, "") still overrides.
  defp override_or_field(nil, from_field), do: from_field
  defp override_or_field(override, _from_field), do: override

  defp translate_error({msg, opts}) do
    case opts[:count] do
      nil -> Gettext.dgettext(LocalCentsWeb.Gettext, "errors", msg, opts)
      count -> Gettext.dngettext(LocalCentsWeb.Gettext, "errors", msg, msg, count, opts)
    end
  end
end
