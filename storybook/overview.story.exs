defmodule Storybook.AboutBondPage do
  use LocalCentsWeb.Storybook.Story, :page

  def render(assigns) do
    ~H"""
    <section class="prose prose-lg prose-slate dark:prose-invert max-w-none font-sans">
      <h2>What is Bond?</h2>

      <p>
        Bond (a name inspired by bond paper) is the LocalCents component library. It captures all
        layout and styling concerns in one place so that LiveView templates can read like a clear
        description of content and intent, with visual details delegated to named components rather
        than scattered Tailwind classes.
      </p>

      <p>
        All components are accessible through the top-level <code>Bond</code> module facade,
        e.g. <code>&lt;Bond.button&gt;</code>, <code>&lt;Bond.input&gt;</code>, <code>&lt;Bond.side_panel&gt;</code>.
      </p>

      <h2>Component categories</h2>

      <h3>Elements</h3>
      <p>
        Single-purpose UI primitives with no knowledge of LocalCents domain concepts, though they are visually styled specifically for LocalCents. They could be
        lifted into any Phoenix app without much to change.
      </p>
      <ul>
        <li>
          <strong>ActionChip</strong> — pill-shaped button with a trailing chevron for dropdowns
        </li>
        <li><strong>Button</strong> — stamp-press button in primary, outline, and square variants</li>
        <li><strong>Checkbox</strong> — slot-based checkbox row in default and pill_row variants</li>
        <li>
          <strong>Input</strong>
          — text input with label, error, and form field support; default, frosted, and search variants
        </li>
        <li><strong>ListView</strong> — scrollable bordered list container</li>
        <li><strong>TagPill</strong> — inline tag badge with a colored dot swatch</li>
      </ul>

      <h3>Composites</h3>
      <p>
        Components that combine Elements to represent domain concepts. They understand
        LocalCents ideas like books and expenses.
      </p>
      <ul>
        <li><strong>BookCell</strong> — a row representing a book document</li>
        <li>
          <strong>ExpenseCell</strong>
          — a row representing a single expense with date, description, amount, and tags
        </li>
      </ul>

      <h3>Layouts</h3>
      <p>
        Structural components that define the shape of pages and panels.
      </p>
      <ul>
        <li>
          <strong>DesktopWindow</strong>
          — the outermost chrome for a desktop-style window with a title bar (used primarly for demos)
        </li>
        <li>
          <strong>InputBar</strong>
          — a toolbar row for new-item entry, with leading and trailing content slots
        </li>
        <li>
          <strong>ListControls</strong> — a toolbar row above a list for search and filter controls
        </li>
        <li>
          <strong>SidePanel</strong>
          — a right-aligned slide-in panel with dimmed overlay, Escape support, and an optional locked state for dirty forms
        </li>
      </ul>

      <h2>Design tokens</h2>
      <p>
        Colors are defined as Tailwind theme tokens in <code>bond.css</code> and referenced
        throughout the component library via utility classes (<code>text-surface-800</code>, <code>bg-surface-50</code>, …) and <code>var(--color-*)</code>. The Tokens section
        of this storybook documents the available palette.
      </p>
    </section>
    """
  end
end
