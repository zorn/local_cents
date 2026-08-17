defmodule Storybook.Composites.ExpenseConflicts do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.ExpenseConflicts.expense_conflicts/1
  def render_source, do: :function

  # Stand-in display-ready conflicts, shaped the way BookLive formats a real summary for
  # the tab: a kept value plus N alternatives, each with its provenance string already
  # built. Enough for the panel to render in isolation.
  defp value(text, device, when_text),
    do: %{value: text, provenance: "Device #{device} · #{when_text}"}

  defp alternative(text, device, when_text, index),
    do: Map.put(value(text, device, when_text), :index, index)

  defp conflict(kept, alternatives) do
    %{
      expense_id: "expense-1",
      field: "description",
      field_label: "Description",
      kept: kept,
      alternatives: alternatives
    }
  end

  # In the app this tab only renders inside the dark editor side-panel, so the catalog wraps
  # each variation in that same `bond-marble` surface — otherwise the light-on-dark colors
  # would preview against a light canvas they are not built for.
  defp panel(inner) do
    ~s|<div class="bond-marble rounded-lg p-5" style="width: 360px;">#{inner}</div>|
  end

  def variations do
    [
      %Variation{
        id: :two_edits,
        description: "One kept value and a single dropped alternative.",
        template: panel("<.psb-variation/>"),
        attributes: %{
          id: "conflicts-two",
          on_make_value: "make_conflict_value",
          on_dismiss: "dismiss_conflict",
          conflicts: [
            conflict(
              value("Espresso", "a1b2c3d4", "Aug 15, 2026, 2:31 PM"),
              [alternative("Latte", "e5f6a7b8", "Aug 15, 2026, 2:44 PM", 0)]
            )
          ]
        }
      },
      %Variation{
        id: :n_edits,
        description: "Three concurrent edits — one kept, two alternatives — never a fixed pair.",
        template: panel("<.psb-variation/>"),
        attributes: %{
          id: "conflicts-n",
          on_make_value: "make_conflict_value",
          on_dismiss: "dismiss_conflict",
          conflicts: [
            conflict(
              value("Espresso", "a1b2c3d4", "Aug 15, 2026, 2:31 PM"),
              [
                alternative("Latte", "e5f6a7b8", "Aug 15, 2026, 2:44 PM", 0),
                alternative("Mocha", "c9d0e1f2", "Aug 15, 2026, 2:52 PM", 1)
              ]
            )
          ]
        }
      }
    ]
  end
end
