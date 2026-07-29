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
          <strong>Button</strong>
          — stamp-press button in primary, outline, square, and destructive variants
        </li>
        <li>
          <strong>EmptyState</strong>
          — dashed-outline placeholder shown where a list would be, when it is empty
        </li>
        <li>
          <strong>Input</strong>
          — text input with label, error, and form field support; default, frosted, and search variants
        </li>
        <li><strong>ListView</strong> — scrollable bordered list container</li>
        <li>
          <strong>LoadingState</strong>
          — the busy counterpart to EmptyState, shown while a list's contents are prepared
        </li>
        <li>
          <strong>Menu</strong>
          — dropdown menu whose panel is <code>position: fixed</code>
          so it escapes the scrolling list card that clips it
        </li>
        <li>
          <strong>Select</strong>
          — styled native <code>&lt;select&gt;</code>, with a blank option for "no selection"
        </li>
      </ul>

      <h3>Composites</h3>
      <p>
        Components that combine Elements to represent domain concepts. They understand
        LocalCents ideas like books, expenses, and categories.
      </p>
      <ul>
        <li><strong>BookCell</strong> — a row representing a book document</li>
        <li>
          <strong>CategoryRow</strong>
          — a category row in the management view, in either its display or edit shape
        </li>
        <li>
          <strong>ExpenseCell</strong>
          — a row representing a single expense with date, description, category, and amount
        </li>
        <li>
          <strong>ReportMatrix</strong>
          — the Report's Category × Month spending grid, with a frozen header row and category column
        </li>
      </ul>

      <h3>Layouts</h3>
      <p>
        Structural components that define the shape of pages and panels.
      </p>
      <ul>
        <li>
          <strong>DesktopWindow</strong>
          — a presentation-only mock of a whole desktop window, used to frame the demos. The real app gets its chrome from the native window plus WindowBar
        </li>
        <li>
          <strong>InputBar</strong>
          — a tinted bar for new-item entry, with leading and trailing content slots
        </li>
        <li>
          <strong>Modal</strong>
          — a centered dismissible dialog for small focused tasks like rename or delete confirmation
        </li>
        <li>
          <strong>SidePanel</strong>
          — a right-aligned slide-in panel with dimmed overlay, Escape support, and an optional locked state for dirty forms
        </li>
        <li>
          <strong>WindowBar</strong>
          — the window's draggable marbled title strip, drawn behind the transparent native title bar
        </li>
      </ul>

      <h2>Design tokens</h2>
      <p>
        Colors are defined as Tailwind theme tokens in <code>bond.css</code> and referenced
        throughout the component library via utility classes (<code>text-surface-800</code>, <code>bg-surface-50</code>, …) and <code>var(--color-*)</code>. The Tokens section
        of this storybook documents the available palette.
      </p>

      <h2>What Bond deliberately does not have</h2>
      <p>
        Bond is trimmed to what the app renders. Components built on a design we later
        cut — <code>TagPill</code>
        and the tag-picking <code>Checkbox</code>
        (superseded by categories), plus <code>ActionChip</code>
        and <code>ListControls</code>
        (a list search/filter toolbar the app never grew) — were removed rather than left
        in the catalog as aspirational entries. A component earns its place here by being
        used, so what you browse is what ships.
      </p>
    </section>
    """
  end
end
