# Moduledoc Style

This guide is our house standard for writing `@moduledoc` (and `@typedoc`)
attributes. It exists so that moduledocs read consistently no matter who — or
what — wrote them, rather than each author making the same judgment calls from
scratch.

It is written for both human contributors and AI agents. When you add or edit a
moduledoc, follow it; when you review one, hold it to this bar.

## The shape of a good moduledoc

We lifted these patterns from the Elixir ecosystem's best-documented modules —
[`Kernel`](https://hexdocs.pm/elixir/Kernel.html),
[`Phoenix`](https://hexdocs.pm/phoenix/Phoenix.html),
[`Phoenix.LiveView`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html),
[`Oban`](https://hexdocs.pm/oban/Oban.html), and
[`Ecto.Repo`](https://hexdocs.pm/ecto/Ecto.Repo.html) — and pared them down to
what fits a project of our size.

**1. Lead with a one-sentence summary.** The first line is special: ExDoc shows
it, on its own, next to the module in every sidebar and index. Make it a single,
complete sentence in the present tense that says what the module *is* or *does*.
Every well-documented library module does this — `Ecto.Repo` opens with "Defines
a repository," `Phoenix.LiveView` with a one-line statement of purpose. Ours
should read the same way — `LocalCents.Tracking.BookServer` opens:

> The per-Book runtime process: one GenServer owns the in-memory Automerge
> document for a single _open_ Book…

Don't bury the summary after a preamble, and don't make the first line depend on
the second to make sense.

**2. Explain the _why_, not the _what_.** A reader can already see the function
names and typespecs. The moduledoc earns its keep by explaining what the code
can't: the module's job in the larger system, the modules it collaborates with,
the invariants it upholds, and the reasoning behind a design that would
otherwise look arbitrary. `LocalCents.Tracking.BookServer` spends its
moduledoc on the persist-then-commit ordering and why Book state never lives
in a socket — exactly the things you can't infer from the callbacks.

**3. Use `##` sections once it grows.** A short moduledoc is just prose. Once it
runs past a few paragraphs, break it into `##` sections with sentence-case
headings (`## How it works`, `## Lifecycle`, `## Layout`) the way `Oban` and
`Phoenix.LiveView` do. This keeps a long doc scannable instead of a wall.

**4. Cross-link deliberately — and don't over-link.** Only a **fully-qualified**
module name autolinks: `` `LocalCents.Tracking.BookStore` `` links, but bare
`` `BookStore` `` or `` `Book` `` renders as plain code. Because full names are
heavy to read, choose the form by intent rather than qualifying everything:

- **Naming a domain concept in prose** — use the short backticked name
  (`` `Book` ``, `` `Expense` ``). It reads as a proper noun and stays light; a
  link on every mention is noise. No link, and that's fine.
- **Pointing the reader at a module to go read it** — use the fully-qualified
  name so it links (`` `LocalCents.Tracking.BookServer` ``). The jump earns the
  longer text.
- **You need the link but the full name breaks the sentence** — ExDoc keeps
  short display text with a working link: `` [`Book`](`LocalCents.Tracking.Book`) ``
  renders as `Book` and links. Use it sparingly; it's the noisiest to author.

Link ADRs and guides by their rendered page (e.g.
`[ADR 0007](0007-book-runtime-and-persistence.html)`,
`[Module Boundaries](module-boundaries.html)`) and issues by full URL. A
moduledoc is a hub; wire it into the rest of the docs — without turning every
noun into a link.

**5. Show a small example when there's an API to demonstrate.** Modules with a
public API that a caller drives benefit from a short fenced ` ```elixir ` block,
the way `Oban` and `Phoenix.LiveView` open with usage snippets. Plain data or
struct modules usually don't need one — their `@typedoc`s carry the weight.

## Moduledoc vs. inline comments vs. ADRs

Three places hold "why," and each has a different job. Put each fact in exactly
one of them and link rather than restate.

- **Moduledoc** — the durable answer to "what is this module and why does it
  exist?" Its audience is someone scanning the module list who has never opened
  the file. Keep it about the module's role and contracts, not line-level
  mechanics.
- **Inline comments** — local, mechanical "why is _this line_ surprising?" notes.
  `LocalCents.Tracking.ExAutomerge`'s comment explaining that the `:erlang.nif_error/1`
  bodies are only a load-failure fallback is a model inline comment: it belongs
  next to the code it explains, not in the moduledoc.
- **ADRs** (`docs/adr/`) — the record of a decision: the problem, the option
  chosen, the alternatives, and the consequences. A moduledoc **summarizes the
  outcome in a sentence and links the ADR**; it never relitigates the decision.
  `…the name is read from inside the document (see [ADR 0007](0007-….html))` is
  the pattern.

## How much is enough

Calibrate the length to the module's kind. A context has three kinds of module,
and `LocalCents.Tracking` has an exemplar of each; use them as templates.

- **The public API module** (`LocalCents.Tracking`) — the context's front door,
  and the fullest moduledoc in a context. Cover the API surface at a high level,
  the runtime model, and how callers identify and refer to entities. Spend words
  here. ("Public API" always names this module, never the context as a whole —
  the context is the whole territory; this is the door into it.)
- **The private implementation** (`LocalCents.Tracking.BookServer`,
  `LocalCents.Tracking.BookStore`, `LocalCents.Tracking.ExAutomerge`,
  `LocalCents.Tracking.Supervisor`) — everything behind that front door. Open by
  stating that the module is private to its context and _why_ (the `Boundary`
  compiler enforces it; see [Module Boundaries](module-boundaries.html)), then
  explain how it works for the maintainer who has to touch it: the invariants it
  upholds, the ordering and broadcast guarantees, the lifecycle. Substantial,
  but focused on behavior rather than the front-door contract.
- **The data types** (`LocalCents.Tracking.Book`, `LocalCents.Tracking.Expense`)
  — a tight summary plus well-written `@typedoc`s. Say what the struct
  represents and how it relates to the rest of the system; let the field types
  speak for the shape. Resist turning these into essays.

When a module has no public meaning of its own (a shim, a generated no-op), use
`@moduledoc false` rather than an apologetic one-liner.

## Typedocs

Document a type with `@typedoc` when the name alone doesn't tell a reader what
the value _means_ or what constraints it carries. `LocalCents.Tracking.Book`'s `id` typedoc
("a UUID string that is also its `.lcbook` file name") is worth its space; a
`@typedoc` that just says "a string" is not. Keep them to a sentence or two.

## Mechanics

- Write in the present tense and in sentence case, including `##` headings.
- Wrap prose to a comfortable width; match the surrounding file.
- Emphasize sparingly with `**bold**` for the one invariant a reader must not
  miss (see how `LocalCents.Tracking.BookServer` bolds "persists it through … first").
- Prefer linking a concept to re-explaining it.

## Exemplars

When in doubt, read these — they are the canonical examples of each kind above:

| Kind                   | Module                            |
| ---------------------- | --------------------------------- |
| Public API module      | `LocalCents.Tracking`             |
| Private implementation | `LocalCents.Tracking.BookServer`  |
| Data type              | `LocalCents.Tracking.Book`        |


