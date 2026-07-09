# Coding standards

How we write code in LocalCents. This file is an **index**: where a rule already
has an authoritative home — a guide, an ADR, or `CLAUDE.md` — this file links
there instead of restating it, matching the house rule of keeping each fact in
one place (see [`docs/moduledoc-style.md`](docs/moduledoc-style.md)). Rules that
had no home in the repo before are written out here in full.

`/code-review`'s Standards axis discovers this file automatically. Keep it current
as conventions land, and add a link here rather than a second copy when a rule
gets its own guide or ADR.

## Elixir & Phoenix

- **Moduledocs & typedocs** — follow the house style in
  [`docs/moduledoc-style.md`](docs/moduledoc-style.md): summary-first line, explain
  the _why_, link ADRs by rendered page, backtick domain concepts (`` `Book` ``).
  Audit every moduledoc you touch against it as an end-of-feature step, not only in
  review.

- **`@impl` names the behaviour; never `@impl true`.** Annotate callbacks with the
  explicit behaviour module — `@impl Phoenix.LiveView`, `@impl Phoenix.Component`,
  `@impl GenServer`, and so on. `@impl true` is ambiguous about which contract the
  callback belongs to; the module name makes it clear at a glance.

- **Component `@spec`s use `Socket.assigns()` and `Rendered.t()`, not `map()`.** For
  a Phoenix component function, alias the types once at the top of the module and
  use the short form:

  ```elixir
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @spec my_component(Socket.assigns()) :: Rendered.t()
  def my_component(assigns) do
  ```

  `Socket.assigns()` is the precise public type (`map | assigns_not_in_socket()`);
  the aliases keep the spec line readable.

- **Name `@spec` arguments whose type doesn't reveal their role.** Annotate a
  primitive or generic argument type with a name so the argument's purpose is legible
  from the spec alone, without opening the function body:

  ```elixir
  # Not this — three opaque types, no idea what each is:
  @spec add_expense(binary(), String.t(), number(), integer()) :: binary()

  # This — each argument reads for itself:
  @spec add_expense(
          doc_bytes :: binary(),
          description :: String.t(),
          amount :: number(),
          time :: integer()
        ) :: binary()
  ```

  Leave a type **bare when it is already self-describing** — a domain type carries
  its own meaning and a name would just be noise: `Book.id()`, `Book.name()`,
  `Expense.t()`, `DateTime.t()` (unless two of the same type sit side by side, e.g.
  `now :: DateTime.t()`), `Socket.assigns()`, `Plug.Conn.t()`. The test is whether a
  reader can tell what the argument is from its type; if not (`binary()`,
  `String.t()`, `integer()`, `map()`, `keyword()`, `term()`), name it. Match the name
  to the function's actual parameter.

- **Stack a long `@spec` one entry per line, return type on its own line.** When a
  spec is too long to read comfortably on one line, put each argument on its own line
  and pull the return type onto its own line after `::`. A newline right after the
  opening `(` nudges the formatter into keeping this shape:

  ```elixir
  @spec add_expense(
          doc_bytes :: binary(),
          description :: String.t(),
          amount :: integer(),
          time :: integer()
        ) ::
          binary()
  ```

  Short specs stay on one line — this is only for the ones that wrap.

- **Name LiveView events in snake_case.** The event strings behind `phx-*`
  bindings and matched in `handle_event/3` are snake_case and describe what they
  represent — `handle_event("email_changed", …)`, `"validate"`, `"save"` — per
  LiveView's [form events](https://hexdocs.pm/phoenix_live_view/form-bindings.html#form-events).

- **Discard an ignored return with `_ = expr`.** When a call is fire-and-forget and
  its result genuinely doesn't matter — e.g. a best-effort `Phoenix.PubSub.broadcast/3`
  once the real work has already succeeded — bind it to `_` so the disinterest is
  explicit rather than a bare dangling expression.

- **Phoenix v1.8 conventions** — the `<Layouts.app flash={@flash} …>` wrapper on
  every LiveView template, the imported `<.input>` / `<.icon>` components,
  authenticated-route / `current_scope` rules, and `Req` as the HTTP client — are
  documented in [`CLAUDE.md`](CLAUDE.md).

## Frontend (JS, CSS, components)

- **No npm.** Keep `package.json` / `node_modules` out of the project as long as
  possible. Vendor JS/CSS dependencies as local files under `assets/vendor/` and
  reference them from `app.js` / `app.css` (e.g. `@plugin "../vendor/<name>"`).

- **Tailwind v4 and hand-authored components** — the `@import "tailwindcss"` /
  `@source` syntax, no `@apply` in raw CSS, and hand-writing components instead of
  daisyUI — are documented in [`CLAUDE.md`](CLAUDE.md).

- **New or changed UI is a Bond component with a mirrored Storybook story.** Add
  components under `lib/local_cents_web/bond/{elements,composites,layouts}/` and
  give each a mirrored story in `storybook/`; a component is not done until it
  appears in Storybook. Where Bond lives and why:
  [ADR 0003](docs/adr/0003-bond-namespace-location.md). Note that
  `bond/composites/expense_cell.ex` and `bond/elements/tag_pill.ex` still encode
  the pre-decision "tags" design and need reworking to the single-Category model
  ([ADR 0005](docs/adr/0005-categories-not-tags.md)).

## Architecture

- **Module boundaries** — contexts are top-level boundaries that export only their
  API, and the `:boundary` compiler must run first. Full conventions and gotchas:
  [`docs/module-boundaries.md`](docs/module-boundaries.md).

- **PubSub topic naming** — `"<kind>:<id>"`, owned by the broadcasting module via a
  `topic/1` function so callers never hand-build the string:
  [ADR 0011](docs/adr/0011-pubsub-topic-naming.md). All architecture decisions live
  in [`docs/adr/`](docs/adr/).

## Rust & Tauri

- Keep Rust minimal — native window management and process lifecycle only.
  Business logic stays in Elixir; do not add a new IPC channel or a
  `#[tauri::command]` for data work. The `elixirkit` PubSub bridge is the intended
  extension point. See [`CLAUDE.md`](CLAUDE.md) and
  [ADR 0006](docs/adr/0006-multi-window-desktop-shell.md).

## Commits & PRs

- Commits and PRs carry **no AI attribution or co-authorship trailers** — attribution
  is to the human author.
- PR titles follow conventional commits with a lowercase-starting subject
  (e.g. `feat: add multi-window desktop shell`).
- `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --check-unused`,
  `format`, `credo --strict`, `dialyzer`, `sobelow`, `test`) must pass before a
  change is considered done.
