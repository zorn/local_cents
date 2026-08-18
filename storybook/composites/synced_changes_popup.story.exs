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

  # A stand-in edit-vs-delete conflict shaped like a summary's `edit_delete_conflicts`, enough
  # for the popup to render its Needs-your-decision rows in isolation.
  defp edit_delete(expense_id, description) do
    %{
      expense_id: expense_id,
      expense: %{
        id: expense_id,
        date: "2026-08-18",
        description: description,
        cost: "4.00",
        category_id: nil
      },
      device: "device-a",
      time: 1_700_000_000
    }
  end

  # The popup positions itself `absolute` (`right-2 top-12`) beneath the bell, so in the app it
  # anchors to the `relative` expenses header. The catalog needs the same relative box, but it
  # must carry an explicit width: the popup is the box's only child and is out of flow, so an
  # auto-width box collapses to zero and the popup drifts a different amount per variation. A
  # fixed-width box centered in the preview frames the popup the same way every time, so the
  # variations line up. Height holds the tallest variation without overlapping the next.
  defp anchored(inner) do
    ~s|<div class="relative mx-auto" style="width: 21rem; min-height: 340px;">#{inner}</div>|
  end

  # The event handlers every variation shares — the popup pushes these on click, inert in the
  # catalog.
  defp handlers do
    %{
      on_open_conflict: "open_conflict",
      on_restore: "restore_expense",
      on_keep_deleted: "keep_deleted",
      on_dismiss_all: "dismiss_all"
    }
  end

  def variations do
    [
      %Variation{
        id: :single,
        description: "One auto-resolved scalar conflict.",
        template: anchored("<.psb-variation/>"),
        attributes:
          Map.merge(handlers(), %{
            id: "synced-changes-single",
            field_conflicts: [conflict("expense-1", "Espresso")],
            edit_delete_conflicts: []
          })
      },
      %Variation{
        id: :several,
        description: "Several auto-resolved conflicts stacked in the group.",
        template: anchored("<.psb-variation/>"),
        attributes:
          Map.merge(handlers(), %{
            id: "synced-changes-several",
            field_conflicts: [
              conflict("expense-1", "Espresso"),
              conflict("expense-2", "Farmers Market"),
              conflict("expense-3", "Monthly transit pass")
            ],
            edit_delete_conflicts: []
          })
      },
      %Variation{
        id: :needs_decision,
        description: "An edit-vs-delete conflict, offering Restore or Keep deleted.",
        template: anchored("<.psb-variation/>"),
        attributes:
          Map.merge(handlers(), %{
            id: "synced-changes-needs-decision",
            field_conflicts: [],
            edit_delete_conflicts: [edit_delete("expense-1", "Espresso")]
          })
      },
      %Variation{
        id: :both_groups,
        description: "Both groups at once — an auto-resolved conflict and a dropped edit.",
        template: anchored("<.psb-variation/>"),
        attributes:
          Map.merge(handlers(), %{
            id: "synced-changes-both",
            field_conflicts: [conflict("expense-1", "Espresso")],
            edit_delete_conflicts: [edit_delete("expense-2", "Farmers Market")]
          })
      }
    ]
  end
end
