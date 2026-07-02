defmodule Storybook.Tokens.Colors do
  use LocalCentsWeb.Storybook.Story, :page

  def doc,
    do:
      "Color tokens defined as Tailwind theme values. All Bond components source their colors from here."

  @shades ~w(50 100 200 300 400 500 600 700 800 900 950)

  @families [
    {"surface", "Blue-tinted neutral — the app backbone (backgrounds, text, borders)"},
    {"primary", "Brand blue — interactive and emphasis"},
    {"secondary", "Terracotta — warm accent"},
    {"tertiary", "Kraft / paper — warm neutral"},
    {"success", "Emerald — positive amounts and confirmations"},
    {"warning", "Amber — cautions"},
    {"error", "Red — destructive actions and negative amounts"}
  ]

  # Shades light enough to need dark text placed on top of them.
  @light_shades ~w(50 100 200 300 400)

  @chrome [
    {"mac-os-close", "#ff5f57", "Close button"},
    {"mac-os-minimize", "#febc2e", "Minimize button"},
    {"mac-os-maximize", "#28c840", "Maximize button"}
  ]

  def render(assigns) do
    assigns = assign(assigns, families: @families, shades: @shades, chrome: @chrome)

    ~H"""
    <section class="prose prose-sm prose-slate max-w-none font-sans">
      <p>
        Colors are defined as Tailwind theme tokens in <code>bond.css</code>
        as Skeleton-style numbered ramps. Each family runs <code>50</code>
        (lightest) → <code>950</code>
        (darkest); Tailwind generates a matching <code>--color-*</code>
        CSS variable and utility classes for each shade, so components reference them via
        utilities like <code>text-surface-800</code>
        or <code>bg-primary-700</code>, and via <code>var(--color-*)</code>
        inline for composite styles. Most families also define a <code>*-contrast-500</code>
        token — a readable text color for placing on top of that family's mid fill — while <code>surface</code>, which spans light and dark backgrounds, defines
        <code>surface-contrast-50</code>
        and <code>surface-contrast-900</code>
        instead.
      </p>
    </section>

    <div class="mt-8 space-y-8 font-sans">
      <.ramp
        :for={{family, description} <- @families}
        family={family}
        description={description}
        shades={@shades}
      />

      <.chrome_group chrome={@chrome} />
    </div>
    """
  end

  defp ramp(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 mb-2">
        <h3 class="text-xs font-bold uppercase tracking-widest text-gray-500 m-0">{@family}</h3>
        <span class="text-sm text-gray-400">{@description}</span>
      </div>
      <div class="flex rounded-lg overflow-hidden border border-gray-200">
        <div
          :for={shade <- @shades}
          class="flex-1 h-16 flex items-end justify-center pb-1"
          style={"background-color: var(--color-#{@family}-#{shade})"}
        >
          <span class={["text-[10px] font-mono", shade_label_class(shade)]}>{shade}</span>
        </div>
      </div>
    </div>
    """
  end

  defp chrome_group(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 mb-2">
        <h3 class="text-xs font-bold uppercase tracking-widest text-gray-500 m-0">
          Chrome
        </h3>
        <span class="text-sm text-gray-400">
          Platform-literal window controls — not part of the palette
        </span>
      </div>
      <div class="divide-y divide-gray-100 border border-gray-200 rounded-lg overflow-hidden">
        <div
          :for={{name, hex, description} <- @chrome}
          class="flex items-center gap-4 px-4 py-3 bg-white"
        >
          <div
            class="w-10 h-10 rounded-md border border-black/10 shrink-0"
            style={"background-color: var(--color-#{name})"}
          >
          </div>
          <code class="text-sm font-mono text-gray-800 w-52 shrink-0">--color-{name}</code>
          <span class="text-sm text-gray-500 flex-1">{description}</span>
          <code class="text-xs font-mono text-gray-400 shrink-0">{hex}</code>
        </div>
      </div>
    </div>
    """
  end

  defp shade_label_class(shade) when shade in @light_shades, do: "text-black/50"
  defp shade_label_class(_shade), do: "text-white/70"
end
