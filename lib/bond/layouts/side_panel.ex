defmodule Bond.Layouts.SidePanel do
  @moduledoc "A right-aligned slide-in panel with a dimmed overlay backdrop."

  use Phoenix.Component

  import LocalCentsWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, required: true, doc: "Heading shown in the panel header"

  attr :on_close, :string,
    required: true,
    doc: "LiveView event name fired by the overlay, close button, and Escape key"

  attr :locked, :boolean,
    default: false,
    doc: "When true all close paths are disabled; use this to guard an unsaved (dirty) form"

  attr :rest, :global, doc: "HTML attributes on the outer wrapper (e.g. id)"

  slot :inner_block, required: true, doc: "Scrollable body content"
  slot :footer, doc: "Action row rendered below the body; omit to show no footer"

  @spec side_panel(Socket.assigns()) :: Rendered.t()
  def side_panel(assigns) do
    ~H"""
    <div
      class="absolute inset-0 flex"
      phx-window-keydown={if !@locked, do: @on_close}
      phx-key="Escape"
      {@rest}
    >
      <%!-- Dim overlay — clicking closes the panel unless locked --%>
      <div
        class="flex-1"
        phx-click={if !@locked, do: @on_close}
        style={"background: color-mix(in srgb, #{Bond.Tokens.color(:title_bar_border)} 50%, transparent)"}
      >
      </div>
      <%!-- Panel --%>
      <div
        class="nb-denim w-80 border-l flex flex-col shadow-2xl"
        style={"border-color: #{Bond.Tokens.color(:title_bar_border)}"}
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-5 pt-4 pb-3 border-b border-white/10">
          <p class="font-nunito text-base font-bold text-white tracking-wide">{@title}</p>
          <button
            phx-click={if !@locked, do: @on_close}
            class="transition-colors"
            style={"color: #{Bond.Tokens.color(if @locked, do: :content_secondary, else: :accent_light)}"}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
        <%!-- Body --%>
        <div class="px-5 py-3 flex-1 overflow-y-auto">
          {render_slot(@inner_block)}
        </div>
        <%!-- Footer --%>
        <%= if @footer != [] do %>
          <div class="flex items-center justify-between px-6 py-4 border-t border-white/10">
            {render_slot(@footer)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
