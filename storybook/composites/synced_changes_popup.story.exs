defmodule Storybook.Composites.SyncedChangesPopup do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.SyncedChangesPopup.synced_changes_popup/1
  def render_source, do: :function

  # Stand-in field conflicts shaped like a real conflict summary's `field_conflicts`,
  # enough for the popup to render its Auto-resolved rows in isolation.
  defp conflict(expense_id, kept) do
    %{
      expense_id: expense_id,
      field: "description",
      kept: %{value: kept, device: "device-a", time: 1_700_000_000},
      alternatives: [%{value: "Latte", device: "device-b", time: 1_700_000_100}]
    }
  end

  def variations do
    [
      %Variation{
        id: :single,
        description: "One auto-resolved scalar conflict.",
        attributes: %{
          id: "synced-changes-single",
          on_open_conflict: "open_conflict",
          on_dismiss_all: "dismiss_all",
          field_conflicts: [conflict("expense-1", "Espresso")]
        }
      },
      %Variation{
        id: :several,
        description: "Several auto-resolved conflicts stacked in the group.",
        attributes: %{
          id: "synced-changes-several",
          on_open_conflict: "open_conflict",
          on_dismiss_all: "dismiss_all",
          field_conflicts: [
            conflict("expense-1", "Espresso"),
            conflict("expense-2", "Farmers Market"),
            conflict("expense-3", "Monthly transit pass")
          ]
        }
      }
    ]
  end
end
