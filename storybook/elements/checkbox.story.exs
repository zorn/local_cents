defmodule Storybook.Elements.Checkbox do
  use LocalCentsWeb.Storybook.Story, :example

  def doc,
    do: "Checkbox with a slot-based label — supports plain text or rich markup like swatches."

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-8 font-sans p-4">
      <%!-- Default variant --%>
      <div>
        <p class="text-xs font-bold uppercase tracking-widest text-gray-400 mb-3">
          Default — plain flex row
        </p>
        <div class="space-y-2">
          <Bond.Elements.Checkbox.checkbox>
            <span class="text-sm text-gray-700">Unchecked option</span>
          </Bond.Elements.Checkbox.checkbox>
          <Bond.Elements.Checkbox.checkbox checked={true}>
            <span class="text-sm text-gray-700">Checked option</span>
          </Bond.Elements.Checkbox.checkbox>
        </div>
      </div>

      <%!-- Pill row variant --%>
      <div>
        <p class="text-xs font-bold uppercase tracking-widest text-gray-400 mb-3">
          pill_row — frosted pill with background and hover
        </p>
        <div class="nb-denim rounded-lg p-3 space-y-1.5">
          <Bond.Elements.Checkbox.checkbox variant="pill_row">
            <span class="w-2.5 h-2.5 rounded-full shrink-0" style="background: #3f7fd6;" />
            <span class="text-sm text-[#c3d2f0]">Food</span>
          </Bond.Elements.Checkbox.checkbox>
          <Bond.Elements.Checkbox.checkbox variant="pill_row" checked={true}>
            <span class="w-2.5 h-2.5 rounded-full shrink-0" style="background: #e0796e;" />
            <span class="text-sm text-[#c3d2f0]">Dining (checked)</span>
          </Bond.Elements.Checkbox.checkbox>
          <Bond.Elements.Checkbox.checkbox variant="pill_row">
            <span class="w-2.5 h-2.5 rounded-full shrink-0" style="background: #6ab97c;" />
            <span class="text-sm text-[#c3d2f0]">Groceries</span>
          </Bond.Elements.Checkbox.checkbox>
        </div>
      </div>
    </div>
    """
  end
end
