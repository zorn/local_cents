defmodule Storybook.Elements.ListView do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Elements.ListView.list_view/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :no_max_height,
        description: "No max height — the list grows with its content.",
        slots: [
          """
          <div class="px-4 py-3">Item One</div>
          <div class="px-4 py-3">Item Two</div>
          <div class="px-4 py-3">Item Three</div>
          """
        ]
      },
      %Variation{
        id: :with_max_height,
        description: "With max_height set — overflowing items become scrollable.",
        attributes: %{max_height: "320px"},
        slots: [
          """
          <div class="px-4 py-3">Item One</div>
          <div class="px-4 py-3">Item Two</div>
          <div class="px-4 py-3">Item Three</div>
          <div class="px-4 py-3">Item Four</div>
          <div class="px-4 py-3">Item Five</div>
          <div class="px-4 py-3">Item Six</div>
          <div class="px-4 py-3">Item Seven</div>
          <div class="px-4 py-3">Item Eight</div>
          """
        ]
      }
    ]
  end
end
