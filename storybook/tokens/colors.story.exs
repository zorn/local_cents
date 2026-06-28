defmodule Storybook.Tokens.Colors do
  use PhoenixStorybook.Story, :page

  def doc, do: "Color tokens defined in Bond.Tokens. All Bond components source their colors from here."

  def render(assigns) do
    ~H"""
    <section class="prose prose-sm prose-slate max-w-none font-sans">
      <p>
        Colors are defined as named tokens in <code>Bond.Tokens</code>. Names describe purpose, not hue.
        Components reference tokens via <code>Bond.Tokens.color(:name)</code> in inline styles,
        keeping all visual decisions visible inside the component file.
      </p>
    </section>

    <div class="mt-8 space-y-8 font-sans">
      <.color_group heading="Accent" tokens={[
        {:accent,         "Primary interactive / brand color"},
        {:accent_dark,    "Pressed and shadow state of the accent"},
        {:button_shadow,  "Neutral dark stamp shadow for buttons"},
      ]} />

      <.color_group heading="Content" tokens={[
        {:content,              "Primary text"},
        {:content_secondary,    "Supporting text and icons"},
        {:content_placeholder,  "Placeholder and hint text"},
      ]} />

      <.color_group heading="Surface & Border" tokens={[
        {:surface,        "Input and card background"},
        {:surface_sunken, "Recessed window body background"},
        {:border,         "Component and chrome borders"},
      ]} />

      <.color_group heading="Title Bar" tokens={[
        {:title_bar_background, "Denim title bar background"},
        {:title_bar_border,     "Title bar bottom border / deep shadow"},
      ]} />

      <.color_group heading="macOS Traffic Lights" tokens={[
        {:mac_os_close,    "Close button"},
        {:mac_os_minimize, "Minimize button"},
        {:mac_os_maximize, "Maximize button"},
      ]} />
    </div>
    """
  end

  defp color_group(assigns) do
    ~H"""
    <div>
      <h3 class="text-xs font-bold uppercase tracking-widest text-gray-400 mb-3">
        {@heading}
      </h3>
      <div class="divide-y divide-gray-100 border border-gray-200 rounded-lg overflow-hidden">
        <%= for {token, description} <- @tokens do %>
          <div class="flex items-center gap-4 px-4 py-3 bg-white">
            <div
              class="w-10 h-10 rounded-md border border-black/10 shrink-0"
              style={"background-color: #{Bond.Tokens.color(token)}"}
            >
            </div>
            <code class="text-sm font-mono text-gray-800 w-52 shrink-0">:{token}</code>
            <span class="text-sm text-gray-500 flex-1">{description}</span>
            <code class="text-xs font-mono text-gray-400 shrink-0">
              {Bond.Tokens.color(token)}
            </code>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
