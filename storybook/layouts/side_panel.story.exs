defmodule Storybook.Layouts.SidePanel do
  use LocalCentsWeb.Storybook.Story, :example

  def doc, do: "Right-aligned modal panel using the native <dialog> element."

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, open_normal: false, open_locked: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("open_normal", _params, socket),
    do: {:noreply, assign(socket, :open_normal, true)}

  def handle_event("close_normal", _params, socket),
    do: {:noreply, assign(socket, :open_normal, false)}

  def handle_event("open_locked", _params, socket),
    do: {:noreply, assign(socket, :open_locked, true)}

  def handle_event("close_locked", _params, socket),
    do: {:noreply, assign(socket, :open_locked, false)}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-8 font-sans">
      <%!-- Normal: all close paths open --%>
      <div>
        <p class="text-xs font-bold uppercase tracking-widest text-gray-400 mb-2">
          Default — Escape, backdrop, or × closes
        </p>
        <div
          class="relative overflow-hidden rounded-lg border bg-surface-sunken border-border-subtle"
          style="height: 380px"
        >
          <div class="p-4">
            <p class="text-sm mb-3 text-content-secondary">
              Background content
            </p>
            <Bond.Elements.Button.button phx-click="open_normal">
              Edit Expense
            </Bond.Elements.Button.button>
          </div>

          <%= if @open_normal do %>
            <Bond.Layouts.SidePanel.side_panel
              id="story-panel-normal"
              title="Edit Expense"
              on_close="close_normal"
            >
              <div class="space-y-3">
                <div>
                  <label class="text-xs font-semibold uppercase tracking-wide block mb-1 text-accent-light">
                    Description
                  </label>
                  <Bond.Elements.Input.input
                    variant="frosted"
                    class="w-full"
                    placeholder="Coffee, groceries…"
                  />
                </div>
                <div>
                  <label class="text-xs font-semibold uppercase tracking-wide block mb-1 text-accent-light">
                    Cost
                  </label>
                  <Bond.Elements.Input.input variant="frosted" class="w-full" placeholder="0.00" />
                </div>
              </div>
              <:footer>
                <button
                  class="text-sm font-bold transition-colors"
                  style="color: #e0796e;"
                  phx-click="close_normal"
                >
                  Delete
                </button>
                <Bond.Elements.Button.button phx-click="close_normal">
                  Save
                </Bond.Elements.Button.button>
              </:footer>
            </Bond.Layouts.SidePanel.side_panel>
          <% end %>
        </div>
      </div>

      <%!-- Locked: dirty-form guard, only Save dismisses --%>
      <div>
        <p class="text-xs font-bold uppercase tracking-widest text-gray-400 mb-2">
          Locked — dirty form guard, only Save dismisses
        </p>
        <div
          class="relative overflow-hidden rounded-lg border bg-surface-sunken border-border-subtle"
          style="height: 380px"
        >
          <div class="p-4">
            <p class="text-sm mb-3 text-content-secondary">
              Background content
            </p>
            <Bond.Elements.Button.button phx-click="open_locked">
              Edit Expense
            </Bond.Elements.Button.button>
          </div>

          <%= if @open_locked do %>
            <Bond.Layouts.SidePanel.side_panel
              id="story-panel-locked"
              title="Edit Expense"
              on_close="close_locked"
              locked={true}
            >
              <div class="space-y-3">
                <div>
                  <label class="text-xs font-semibold uppercase tracking-wide block mb-1 text-accent-light">
                    Description
                  </label>
                  <Bond.Elements.Input.input
                    variant="frosted"
                    class="w-full"
                    placeholder="Whole Foods grocery run"
                  />
                </div>
                <div>
                  <label class="text-xs font-semibold uppercase tracking-wide block mb-1 text-accent-light">
                    Cost
                  </label>
                  <Bond.Elements.Input.input variant="frosted" class="w-full" placeholder="127.43" />
                </div>
                <p class="text-xs" style="color: rgba(255,255,255,0.45);">
                  Form has unsaved changes — Escape, backdrop, and × are disabled.
                </p>
              </div>
              <:footer>
                <button
                  class="text-sm font-bold transition-colors"
                  style="color: rgba(224,121,110,0.4);"
                >
                  Delete
                </button>
                <Bond.Elements.Button.button phx-click="close_locked">
                  Save
                </Bond.Elements.Button.button>
              </:footer>
            </Bond.Layouts.SidePanel.side_panel>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
