defmodule LocalCentsWeb.Bond.Elements.ListView do
  @moduledoc "A scrollable, bordered list container for notebook-themed row content."

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :max_height, :string,
    default: nil,
    doc:
      "Optional CSS max-height for the scrollable area, e.g. \"320px\". Omit to grow with content."

  slot :header, doc: "Optional content rendered above the scrollable area, inside the container"
  slot :inner_block, required: true, doc: "Row content rendered inside the scrollable area"

  @spec list_view(Socket.assigns()) :: Rendered.t()
  def list_view(assigns) do
    ~H"""
    <div class="m-4 bg-white rounded-lg overflow-hidden border border-surface-200 shadow-md shadow-primary-500/20">
      <%!-- If we are presenting a header, we need a border below it. --%>
      <%= if @header != [] do %>
        <div class="border-b border-surface-200">
          {render_slot(@header)}
        </div>
      <% end %>
      <div
        class="overflow-y-auto divide-y divide-surface-200/60"
        style={@max_height && "max-height: #{@max_height}"}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
