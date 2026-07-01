defmodule LocalCentsWeb.Bond.Elements.Input do
  @moduledoc """
  A notebook-themed input element.

  Always renders an outer `<div>` wrapper containing an optional label, the
  input element itself, and any validation error messages. This means the
  component is self-contained — callers do not need to wrap it in their own
  `<div>` or manually add a `<label>`.

  ## Variants

  The `variant` attr controls the visual style of the input element:

  - **`"default"`** — an underline-only style suited for light backgrounds.
    The bottom border uses the notebook tint accent color.
  - **`"frosted"`** — a semi-transparent frosted-glass style for use inside
    dark panel backgrounds (e.g. `Bond.Layouts.SidePanel`).
  - **`type="search"`** — a pill-shaped field with an inset magnifying glass
    icon. Only works with `variant="default"`; combining search with another
    variant raises `ArgumentError`.

  ## Label

  Pass `label="My Label"` to render a small uppercase label above the input.
  Omit it (the default) to render no label at all — there is no opt-out attr
  needed. Label color is derived from the variant: `accent_light` for frosted,
  `content_secondary` for default.

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

  # FIXME: Maybe accept a known list of atoms.
  attr :type, :string,
    default: "text",
    doc: "HTML input type; \"search\" renders a pill field with a magnifying glass icon"

  attr :variant, :string,
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

  attr :rest, :global, doc: "HTML attributes (placeholder, phx-*, disabled, etc.)"

  @spec input(Socket.assigns()) :: Rendered.t()
  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      case Phoenix.Component.used_input?(field) do
        true -> field.errors
        false -> []
      end

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
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
        <div class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none text-content-secondary">
          <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5" />
        </div>
        <input
          type="search"
          id={@id}
          name={@name}
          value={@value}
          class="bond-input pl-7 pr-3 py-1.5 text-sm border nb-t-border rounded-full focus:outline-none w-full transition-shadow focus:[box-shadow:0_0_0_4px_rgba(30,64,175,0.12)] bg-surface text-content"
          style="--bond-placeholder: var(--color-content-placeholder)"
          {@rest}
        />
      </div>
      <.input_errors errors={@errors} />
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
        class="bond-input w-full px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none focus:[box-shadow:0_0_0_3px_rgba(108,160,234,0.35)] text-content border-accent-light bg-surface-frosted"
        style="--bond-placeholder: var(--color-content-placeholder)"
        {@rest}
      />
      <.input_errors errors={@errors} />
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
        class="bond-input w-full px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none text-content border-accent bg-surface"
        style="--bond-placeholder: var(--color-content-placeholder)"
        {@rest}
      />
      <.input_errors errors={@errors} />
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
      style="color: #e0796e;"
    >
      {msg}
    </p>
    """
  end

  defp label_color_class("frosted"), do: "text-accent-light"
  defp label_color_class(_), do: "text-content-secondary"

  defp translate_error({msg, opts}) do
    case opts[:count] do
      nil -> Gettext.dgettext(LocalCentsWeb.Gettext, "errors", msg, opts)
      count -> Gettext.dngettext(LocalCentsWeb.Gettext, "errors", msg, msg, count, opts)
    end
  end
end
