defmodule Storybook.Layouts.OfflineToggle do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Layouts.OfflineToggle.offline_toggle/1
  def render_source, do: :function

  # The pill is `position: fixed`, which in the catalog would pin it to the corner of the
  # Storybook page rather than the example. A `transform` on the wrapper makes it a
  # containing block for fixed descendants, so it lands in this stand-in window exactly as
  # it would in a real one — no override of the component needed.
  defp window(inner) do
    """
    <div class="bond-window-paper overflow-hidden rounded-lg" style="width: 520px; height: 180px; transform: translateZ(0);">
      <div class="p-4 text-sm text-surface-700">Window content.</div>
      #{inner}
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :online,
        description:
          "The resting look while the link is live. Clicking it takes the Mac offline so " <>
            "the two peers diverge. It appears only on the desktop, and only when a sync " <>
            "link exists.",
        attributes: %{online: true},
        template: window("<.psb-variation/>")
      },
      %Variation{
        id: :offline,
        description:
          "Suspended: tinted amber so the operator can see at a glance that edits are " <>
            "diverging. Clicking it resumes the link and reconciles both sides.",
        attributes: %{online: false},
        template: window("<.psb-variation/>")
      }
    ]
  end
end
