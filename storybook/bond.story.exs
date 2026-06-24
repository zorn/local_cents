defmodule Storybook.AboutBondPage do
  use PhoenixStorybook.Story, :page
  def doc, do: "An overview of the Bond user interface library and its features."

  def render(assigns) do
    ~H"""
    <section class="prose prose-sm prose-slate dark:prose-invert max-w-none font-sans">
      <h2>Why a named component system?</h2>

      <p>
        As LocalCents grows, we want LiveView templates to stay concise and easy to read. Without a
        shared component system, templates accumulate hard-coded Tailwind utility classes, repeated
        layout logic, and one-off styling decisions that drift out of sync with each other over time.
      </p>

      <p>
        Bond (a silly name, inspired by bond paper) is our answer to that problem. It is a component library that captures all layout
        and styling concerns in one place. LiveView templates should read like a clear description of
        content and intent, with the visual details delegated to Bond components.
      </p>

      <h2>How components are organized</h2>

      <p>Bond components are grouped into three categories:</p>

      <h3>Elements</h3>
      <p>
        The raw building blocks of the UI — buttons, inputs, badges, icons, and other small,
        single-purpose elements. Elements have no knowledge of LocalCents domain concepts. They
        could be lifted into any Phoenix app unchanged.
      </p>

      <h3>Composites</h3>
      <p>
        Components that combine Elements to represent a meaningful piece of the LocalCents
        application — a transaction row, an account card, a category tag. Composites understand
        domain concepts like amounts, categories, and accounts. They are the primary components
        referenced in feature LiveView templates.
      </p>

      <h3>Layouts</h3>
      <p>
        Structural components that define the skeleton of pages — the page shell, sidebar, section
        headers, and empty states. Layouts are app-chrome: they give pages their shape and
        navigation, but they carry no domain-specific content of their own.
      </p>
    </section>
    """
  end
end
