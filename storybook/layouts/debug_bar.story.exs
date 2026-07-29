defmodule Storybook.Layouts.DebugBar do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Layouts.DebugBar.debug_bar/1
  def render_source, do: :function

  # The bar is `position: fixed`, which in the catalog would pin it to the corner of
  # the Storybook page rather than the example. A `transform` on the wrapper makes it a
  # containing block for fixed descendants, so the bar lands in this stand-in window
  # exactly as it would in a real one — no override of the component needed.
  defp window(inner) do
    """
    <div class="bond-window-paper overflow-hidden rounded-lg" style="width: 520px; height: 180px; transform: translateZ(0);">
      <div class="p-4 text-sm text-surface-700">Window content.</div>
      #{inner}
    </div>
    """
  end

  @links [
    %{label: "Storybook", href: "#"},
    %{label: "Docs", href: "#"},
    %{label: "LiveDashboard", href: "#"}
  ]

  def variations do
    [
      %Variation{
        id: :collapsed,
        description:
          "At rest. Only the pill shows, so it covers nothing that matters — click it to " <>
            "expand. It appears only when the app is driven from a browser in development.",
        attributes: %{links: @links},
        template: window("<.psb-variation/>")
      },
      %Variation{
        id: :expanded,
        description: "Open, showing the developer links. Each opens in a new tab.",
        attributes: %{links: @links, open: true},
        template: window("<.psb-variation/>")
      },
      %Variation{
        id: :single_link,
        description: "The row is built from whatever links it is handed.",
        attributes: %{links: [%{label: "Docs", href: "#"}], open: true},
        template: window("<.psb-variation/>")
      }
    ]
  end
end
