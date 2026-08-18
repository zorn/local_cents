defmodule LocalCentsWeb.ConflictPresenter do
  @moduledoc """
  Maps a Book's scalar conflicts into the display-ready shape
  `LocalCentsWeb.Bond.Composites.ExpenseConflicts` renders in the editor's Conflicts tab.

  The panel stays domain-agnostic — it renders strings, never a raw Automerge actor id or a
  unix timestamp (mirroring how `ExpenseCell` takes an `amount_display` string). This module
  is the formatting seam: it builds the field label and each value's provenance — which device
  made the edit and when. Its input is the `field_conflict` list from a
  `t:LocalCents.Tracking.BookDocument.conflict_summary/0`, already filtered to one Expense.

  Provenance names a device by the raw actor id shortened to a stable token — there is no
  friendly device-name mapping yet, a later concern — and drops the "when" half when a change
  carried no usable time rather than inventing one. Times render in the viewer's own zone.
  """

  @typedoc "One value in the tab: the kept winner or an alternative, formatted for display."
  @type value_view() :: %{value: String.t(), provenance: String.t()}

  @typedoc """
  One conflicted field ready to render: a label, the kept value, and each alternative tagged
  with the `index` a "Make this the value" click sends back to name which one to override to.
  """
  @type conflict_view() :: %{
          expense_id: String.t(),
          field: String.t(),
          field_label: String.t(),
          kept: value_view(),
          alternatives: [%{index: non_neg_integer(), value: String.t(), provenance: String.t()}]
        }

  @doc """
  Shapes `field_conflicts` (already narrowed to the open Expense) into the Conflicts tab's
  display models, formatting every value's provenance in `time_zone`.
  """
  @spec views(field_conflicts :: [map()], time_zone :: String.t()) :: [conflict_view()]
  def views(field_conflicts, time_zone) do
    Enum.map(field_conflicts, &view(&1, time_zone))
  end

  @doc """
  The display label for a stored scalar-field name, via `Phoenix.Naming.humanize/1`: it
  drops a trailing `_id`, spaces out underscores, and capitalizes — so `category_id` reads
  "Category" rather than leaking the column name as "Category_id", and `description` reads
  "Description". Public so the Synced changes popup labels a field the same way the
  Conflicts tab does.
  """
  @spec field_label(field :: String.t()) :: String.t()
  def field_label(field), do: Phoenix.Naming.humanize(field)

  @doc """
  The value of the `index`-th alternative of the conflict on `expense_id`'s `field` as
  `{:ok, value}`, or `:error` when the conflict or index no longer resolves (a resync dropped
  it out from under a click). `value` may itself be `nil` — the register allows it — which is
  why an `:error` tuple, not a bare `nil`, signals the lookup miss. `index` arrives as the
  string a `phx-value` carries.
  """
  @spec alternative_value(
          field_conflicts :: [map()],
          expense_id :: String.t(),
          field :: String.t(),
          index :: String.t()
        ) :: {:ok, String.t() | nil} | :error
  def alternative_value(field_conflicts, expense_id, field, index) do
    # `i >= 0` guards `Enum.at/2`'s negative-index wraparound: a crafted `phx-value-index` of
    # "-1" would otherwise select the last alternative instead of missing.
    with %{alternatives: alternatives} <- find(field_conflicts, expense_id, field),
         {i, ""} when i >= 0 <- Integer.parse(index),
         %{value: value} <- Enum.at(alternatives, i) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp find(field_conflicts, expense_id, field) do
    Enum.find(field_conflicts, &(&1.expense_id == expense_id and &1.field == field))
  end

  defp view(conflict, time_zone) do
    %{
      expense_id: conflict.expense_id,
      field: conflict.field,
      field_label: field_label(conflict.field),
      kept: value_view(conflict.kept, time_zone),
      alternatives:
        conflict.alternatives
        |> Enum.with_index()
        |> Enum.map(fn {alternative, index} ->
          Map.put(value_view(alternative, time_zone), :index, index)
        end)
    }
  end

  defp value_view(%{value: value, device: device, time: time}, time_zone) do
    %{value: display_value(value), provenance: provenance(device, time, time_zone)}
  end

  # A scalar description is a string, but the register's value type allows nil, so show an
  # honest placeholder rather than a blank line if a future field ever clears to nil.
  defp display_value(nil), do: "(empty)"
  defp display_value(value), do: value

  defp provenance(device, time, time_zone) do
    ["Device " <> String.slice(device, 0, 8), format_time(time, time_zone)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp format_time(nil, _time_zone), do: nil

  defp format_time(unix, time_zone) do
    with {:ok, utc} <- DateTime.from_unix(unix),
         {:ok, local} <- DateTime.shift_zone(utc, time_zone) do
      Calendar.strftime(local, "%b %-d, %Y, %-I:%M %p")
    else
      _ -> nil
    end
  end
end
