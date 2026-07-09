defmodule LocalCentsWeb.Layouts do
  @moduledoc """
  The app's shared layout shell and flash rendering.

  `app/1` is the outer wrapper every LiveView template begins with; it renders
  the shared chrome and the flash group around the page's `inner_block`. Because
  it owns flash rendering, `flash_group/1` lives here too — it is **not** called
  from anywhere else. The `layouts/*` templates embedded here (`root`, `app`)
  provide the surrounding HTML document.
  """
  use LocalCentsWeb, :html

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app's window shell.

  Every LiveView template begins with this wrapper. It sits the page on the
  window's paper background and renders the flash group around the
  `inner_block` — nothing more. LocalCents runs as native windows (see
  [ADR 0006](0006-multi-window-desktop-shell.html)), so the generated Phoenix
  marketing header was removed; each screen owns its own layout inside the
  window.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  @spec app(Socket.assigns()) :: Rendered.t()
  def app(assigns) do
    ~H"""
    <main class="bond-window-paper min-h-screen">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(Socket.assigns()) :: Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
