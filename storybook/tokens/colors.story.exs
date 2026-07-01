defmodule Storybook.Tokens.Colors do
  use LocalCentsWeb.Storybook.Story, :page

  def doc,
    do:
      "Color tokens defined as Tailwind theme values. All Bond components source their colors from here."

  def render(assigns) do
    ~H"""
    <section class="prose prose-sm prose-slate max-w-none font-sans">
      <p>
        Colors are defined as Tailwind theme tokens in <code>bond.css</code>. Names describe
        purpose, not hue. Tailwind generates a matching <code>--color-*</code>
        CSS variable and
        utility classes for each one, so components reference them via utilities like
        <code>text-content</code>
        or <code>bg-surface</code>
        where a single color property is set,
        and via <code>var(--color-*)</code>
        inline for CSS-variable injection and composite styles.
      </p>
    </section>

    <div class="mt-8 space-y-8 font-sans">
      <.color_group
        heading="Accent"
        tokens={[
          {"accent", "#1e40af", "Primary interactive / brand color"},
          {"accent-dark", "#1b3a9a", "Pressed and shadow state of the accent"},
          {"accent-light", "#6ca0ea", "Lighter accent for dark / frosted panel contexts"},
          {"button-shadow", "#1e293b", "Neutral dark stamp shadow for buttons"}
        ]}
      />

      <.color_group
        heading="Content"
        tokens={[
          {"content", "#22335c", "Primary text"},
          {"content-secondary", "#6980b0", "Supporting text and icons"},
          {"content-placeholder", "#a0b4d0", "Placeholder and hint text"}
        ]}
      />

      <.color_group
        heading="Surface & Border"
        tokens={[
          {"surface", "#ffffff", "Input and card background"},
          {"surface-sunken", "#cce0f5", "Recessed window body background"},
          {"surface-frosted", "#b8d0ee", "Frosted blue input surface for dark panels"},
          {"border", "#a8c0e0", "Component and chrome borders"},
          {"border-subtle", "#c3d2f0", "Lighter divider and card borders"}
        ]}
      />

      <.color_group
        heading="Currency"
        tokens={[
          {"positive-currency", "#3f9d6c", "Positive / income amounts"}
        ]}
      />

      <.color_group
        heading="Title Bar"
        tokens={[
          {"title-bar-background", "#1e2d4d", "Denim title bar background"},
          {"title-bar-border", "#0d1a35", "Title bar bottom border / deep shadow"}
        ]}
      />

      <.color_group
        heading="macOS Traffic Lights"
        tokens={[
          {"mac-os-close", "#ff5f57", "Close button"},
          {"mac-os-minimize", "#febc2e", "Minimize button"},
          {"mac-os-maximize", "#28c840", "Maximize button"}
        ]}
      />
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
        <%= for {name, hex, description} <- @tokens do %>
          <div class="flex items-center gap-4 px-4 py-3 bg-white">
            <div
              class="w-10 h-10 rounded-md border border-black/10 shrink-0"
              style={"background-color: var(--color-#{name})"}
            >
            </div>
            <code class="text-sm font-mono text-gray-800 w-52 shrink-0">--color-{name}</code>
            <span class="text-sm text-gray-500 flex-1">{description}</span>
            <code class="text-xs font-mono text-gray-400 shrink-0">{hex}</code>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
