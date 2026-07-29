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
  window's paper background, draws a draggable title bar the paper texture paints
  up into, and renders the flash group around the `inner_block`. LocalCents runs
  as native windows (see [ADR 0006](0006-multi-window-desktop-shell.html)), so the
  generated Phoenix marketing header was removed; each screen owns its own layout
  inside the window.

  The native macOS title bar is transparent with its text hidden (see
  [ADR 0013](0013-transparent-native-title-bar.html)), so the HTML bar rendered
  here is what the user sees: the real traffic lights float over its left edge and
  `window_title` shows centered. The bar is `data-tauri-drag-region`, making that
  strip drag the native window. It is a fixed-height flex child, so the content
  below it is reserved clear of the traffic lights automatically.

  The same shell serves both clients (see [ADR 0023](0023-browser-as-a-second-client.html)).
  `client` is required rather than defaulted so a view that forgets to pass it fails the
  build instead of quietly rendering the wrong chrome. In the `:browser` client the title
  bar's drag region is dropped and `back_path` — passed by the document-window views, not
  by the library itself — becomes the way back, and a floating debug bar appears when the
  dev routes are on.

  ## Examples

      <Layouts.app flash={@flash} client={@client} window_title="Library">
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :window_title, :string,
    default: nil,
    doc: "text shown centered in the title bar; the native title text is hidden"

  attr :client, :atom,
    required: true,
    values: [:desktop, :browser],
    doc: "which client the page is rendering into (see `LocalCentsWeb.Client`)"

  attr :back_path, :string,
    default: nil,
    doc: "where the title bar's browser-only back link goes; omitted on the library itself"

  slot :inner_block, required: true

  @spec app(Socket.assigns()) :: Rendered.t()
  def app(assigns) do
    assigns = assign(assigns, :debug_links, debug_links())

    ~H"""
    <main class="bond-window-paper flex h-screen flex-col overflow-hidden">
      <%!-- The paper texture on <main> paints up into the transparent native title
      bar; this strip drags the window and shows the centered title over the native
      traffic lights (ADR 0013). It is a fixed-height flex child, so the content
      below reserves clear of the traffic lights on its own. --%>
      <Bond.window_bar title={@window_title} client={@client} back_path={@back_path} />

      <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />

    <%!-- Rendered outside <main> so the floating pill is never subject to the window
    shell's `overflow-hidden`. --%>
    <Bond.debug_bar :if={@client == :browser and @debug_links != []} links={@debug_links} />
    """
  end

  # The developer links the debug bar offers, or none when they would not work.
  #
  # Built at compile time rather than filtered at runtime because `~p"/dev/dashboard"`
  # only *exists* when `:dev_routes` is on — under any other config a verified route to
  # it would not compile. Gating the list on the same flag the router uses keeps the
  # bar and its targets appearing and disappearing together, so it can never offer a
  # dead link.
  if Application.compile_env(:local_cents, :dev_routes, false) do
    defp debug_links do
      [
        %{label: "Storybook", href: ~p"/storybook"},
        # Not `/doc/index.html` directly: `LocalCentsWeb.DevDocsLive` stands in front of
        # the generated docs so missing or stale ones can offer to rebuild themselves.
        %{label: "Docs", href: ~p"/dev/docs"},
        %{label: "LiveDashboard", href: ~p"/dev/dashboard"}
      ]
    end
  else
    defp debug_links, do: []
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
