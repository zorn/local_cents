defmodule LocalCentsWeb.Bond.Layouts.DesktopWindow do
  @moduledoc """
  A macOS-style desktop window chrome with a denim title bar and twill-textured background.
  Renders traffic-light buttons and a centered title above slot content.
  """

  use Phoenix.Component
  alias LocalCentsWeb.Bond

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  attr :title, :string, required: true, doc: "Text displayed centered in the title bar"

  slot :inner_block, required: true, doc: "Content rendered below the title bar"

  @spec desktop_window(Socket.assigns()) :: Rendered.t()
  def desktop_window(assigns) do
    ~H"""
    <div
      class="rounded-xl overflow-hidden shadow-lg"
      style={"border: 1px solid #{Bond.Tokens.color(:border)}; box-shadow: 0 10px 15px -3px #{Bond.Tokens.color(:accent)}33; --nb-t: #{Bond.Tokens.color(:accent)}; --nb-t-dk: #{Bond.Tokens.color(:accent_dark)}; background-color: #{Bond.Tokens.color(:surface_sunken)}; background-image: repeating-linear-gradient(45deg, rgba(255,255,255,0.30) 0px, rgba(255,255,255,0.30) 1px, transparent 1px, transparent 5px)"}
    >
      <div
        class="relative flex items-center pl-3 pr-4 py-2 select-none"
        style={"border-bottom: 1px solid #{Bond.Tokens.color(:title_bar_border)}; background-color: #{Bond.Tokens.color(:title_bar_background)}; background-image: radial-gradient(ellipse at 18% 32%, rgba(63,127,214,0.28) 0%, transparent 52%), radial-gradient(ellipse at 78% 72%, rgba(20,35,75,0.65) 0%, transparent 44%), radial-gradient(ellipse at 50% 5%, rgba(34,51,92,0.35) 0%, transparent 58%)"}
      >
        <div class="flex items-center gap-2 z-10">
          <button
            style={"background: #{Bond.Tokens.color(:mac_os_close)}"}
            class="w-3 h-3 rounded-full border border-black/20"
          >
          </button>
          <button
            style={"background: #{Bond.Tokens.color(:mac_os_minimize)}"}
            class="w-3 h-3 rounded-full border border-black/20"
          >
          </button>
          <button
            style={"background: #{Bond.Tokens.color(:mac_os_maximize)}"}
            class="w-3 h-3 rounded-full border border-black/20"
          >
          </button>
        </div>
        <span class="absolute inset-0 flex items-center justify-center font-nunito text-sm font-semibold text-white/90 pointer-events-none">
          {@title}
        </span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
