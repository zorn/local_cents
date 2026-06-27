defmodule Storybook.Layouts.DesktopWindow do
  use PhoenixStorybook.Story, :component

  def function, do: &Bond.Layouts.DesktopWindow.desktop_window/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "A window with a title and placeholder content.",
        attributes: %{
          title: "Family Expenses"
        },
        slots: [
          """
          <div style="width: 520px; padding: 16px;">
            <div style="background: white; border-radius: 8px; border: 1px solid #c3d2f0; overflow: hidden;">
              <div style="padding: 10px 16px; border-bottom: 1px solid #c3d2f0; background: #e8f0fb;">
                <div style="height: 14px; width: 180px; background: #c3d2f0; border-radius: 4px;"></div>
              </div>
              <div>
                <div style="display: flex; align-items: center; gap: 16px; padding: 12px 16px; border-bottom: 1px solid #eaf0fb;">
                  <div style="height: 12px; width: 72px; background: #c3d2f0; border-radius: 4px;"></div>
                  <div style="height: 12px; flex: 1; background: #e2eaf6; border-radius: 4px;"></div>
                  <div style="height: 12px; width: 48px; background: #c3d2f0; border-radius: 4px;"></div>
                </div>
                <div style="display: flex; align-items: center; gap: 16px; padding: 12px 16px; border-bottom: 1px solid #eaf0fb;">
                  <div style="height: 12px; width: 72px; background: #c3d2f0; border-radius: 4px;"></div>
                  <div style="height: 12px; flex: 1; background: #e2eaf6; border-radius: 4px;"></div>
                  <div style="height: 12px; width: 48px; background: #c3d2f0; border-radius: 4px;"></div>
                </div>
                <div style="display: flex; align-items: center; gap: 16px; padding: 12px 16px;">
                  <div style="height: 12px; width: 72px; background: #c3d2f0; border-radius: 4px;"></div>
                  <div style="height: 12px; flex: 1; background: #e2eaf6; border-radius: 4px;"></div>
                  <div style="height: 12px; width: 48px; background: #c3d2f0; border-radius: 4px;"></div>
                </div>
              </div>
            </div>
          </div>
          """
        ]
      }
    ]
  end
end
