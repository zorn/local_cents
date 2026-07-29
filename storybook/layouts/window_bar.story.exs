defmodule Storybook.Layouts.WindowBar do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Layouts.WindowBar.window_bar/1
  def render_source, do: :function

  # In the app the real macOS traffic lights sit on this marble bar; the catalog has
  # no native chrome, so each variation wraps the bar over a paper body to stand in
  # for the window it tops.
  @dots_note "No red/amber/green dots here — those are the real macOS window controls, drawn " <>
               "by the OS on top of this strip because the shell makes the native title bar " <>
               "transparent (ADR 0013). Storybook has no native chrome, so the bar renders alone."

  defp paper(inner) do
    """
    <div class="bond-window-paper rounded-lg overflow-hidden" style="width: 520px;">
      #{inner}
      <div class="p-4 text-sm text-surface-700">Window content.</div>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        description: "The library window's title bar. #{@dots_note}",
        attributes: %{title: "Library", client: :desktop},
        template: paper("<.psb-variation/>")
      },
      %Variation{
        id: :untitled,
        description: "No title — a bare draggable strip.",
        attributes: %{client: :desktop},
        template: paper("<.psb-variation/>")
      },
      %Variation{
        id: :browser,
        description:
          "Driven from a browser instead of the native shell (ADR 0023): no drag region, " <>
            "and the space the traffic lights would occupy carries the way back.",
        attributes: %{title: "Family Expenses", client: :browser, back_path: "/library"},
        template: paper("<.psb-variation/>")
      },
      %Variation{
        id: :browser_at_the_library,
        description:
          "The browser client on the library itself — no back link, because this is where " <>
            "the back link goes.",
        attributes: %{title: "Library", client: :browser},
        template: paper("<.psb-variation/>")
      }
    ]
  end
end
