defmodule Bond.Elements.Input do
  @moduledoc "A notebook-themed input element. Supports text (underline style) and search (pill with icon) variants."

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

  attr :class, :string,
    default: nil,
    doc: "Additional classes; applied to wrapper div for search, input element otherwise"

  attr :rest, :global,
    include: ~w(value),
    doc: "HTML attributes (id, placeholder, value, phx-*, etc.)"

  @spec input(Socket.assigns()) :: Rendered.t()
  def input(%{type: "search", variant: v} = _assigns) when v != "default" do
    raise ArgumentError,
          "Bond.Elements.Input: variant=#{inspect(v)} is not supported with type=\"search\""
  end

  def input(%{type: "search"} = assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div
        class="absolute inset-y-0 left-2.5 flex items-center pointer-events-none"
        style={"color: #{Bond.Tokens.color(:content_secondary)}"}
      >
        <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5" />
      </div>
      <input
        type="search"
        class="bond-input font-nunito pl-7 pr-3 py-1.5 text-sm border nb-t-border rounded-full focus:outline-none w-full transition-shadow focus:[box-shadow:0_0_0_4px_rgba(30,64,175,0.12)]"
        style={"background: #{Bond.Tokens.color(:surface)}; color: #{Bond.Tokens.color(:content)}; --bond-placeholder: #{Bond.Tokens.color(:content_placeholder)}"}
        {@rest}
      />
    </div>
    """
  end

  def input(%{variant: "frosted"} = assigns) do
    ~H"""
    <input
      type={@type}
      class={[
        "bond-input font-nunito px-3 py-1.5 text-sm border-b-2 rounded-sm transition-shadow focus:outline-none focus:[box-shadow:0_0_0_3px_rgba(108,160,234,0.35)]",
        @class
      ]}
      style={"color: #{Bond.Tokens.color(:content)}; border-color: #{Bond.Tokens.color(:accent_light)}; background: #{Bond.Tokens.color(:surface_frosted)}; --bond-placeholder: #{Bond.Tokens.color(:content_placeholder)}"}
      {@rest}
    />
    """
  end

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
