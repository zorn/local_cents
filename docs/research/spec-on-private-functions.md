# `@spec` on private functions (`defp`)

> Research note behind a coding-standards decision: when we add `@spec`
> typespecs to LocalCents code (and run Dialyzer), should we spec **public
> functions only**, or also **private helpers** (`defp`)? Sources are primary:
> the official Elixir Typespecs guide, the Dialyxir README, the Erlang Dialyzer
> reference, Credo's installed `Readability.Specs` check, and a direct
> measurement of the `@spec`/`def`/`defp` pattern in the libraries already
> vendored under `deps/`. Secondary blog posts and forum opinions were used only
> to locate primary sources, not as authorities.

## Question

`@spec` is legal on `defp` — the compiler accepts it and Dialyzer will check it.
So the question is not *can* we, but *should* we: is the community norm to spec
the whole surface (public + private), or to spec the public API and let private
helpers go unspecced? The framing matters most for a project that runs Dialyzer,
because the natural intuition ("more specs = more type safety") turns out to be
largely wrong for private functions — Dialyzer infers their types either way.

## What the official Elixir docs say

The [Typespecs guide](https://elixir.hexdocs.pm/typespecs.html) defines what a
spec *is* and what it's *for*, but is deliberately silent on the public/private
question. It gives two motivations, both of which point at the public surface:

- specs "provide documentation (for example, tools such as `ExDoc` show type
  specifications in the documentation)", and
- they're "used by tools such as Dialyzer, that can analyze code with typespecs
  to find type inconsistencies and possible bugs".

The first motivation is inert for `defp`: ExDoc does not render documentation for
private functions at all, so a spec on a `defp` produces no published
documentation. That leaves only the second (Dialyzer) motivation to justify
specing a private function — and the next section shows that motivation is weak.

The [community Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
adds only a placement rule, not a scope rule: "Place specifications right before
the function definition, after the `@doc`, without separating them by a blank
line." It never mandates specs on every function, public or private.

## How Dialyzer actually treats private functions

This is the crux. Dialyzer does **not** need specs to reason about private
functions, because it infers a *success typing* for every function on its own.

- The [Erlang Dialyzer reference](https://www.erlang.org/doc/apps/dialyzer/dialyzer_chapter.html)
  states that Dialyzer "checks and consumes function specs, yet does not require
  them," and that it "infers types for all top-level functions in a module." When
  a spec is present, Dialyzer compares its inferred success typing against the
  declared spec; when no spec is present, it still derives and uses the inferred
  typing.
- The [Dialyxir README](https://dialyxir.hexdocs.pm/readme.html) says the same in
  Elixir-facing terms: "The analysis can be improved by inclusion of type hints
  (called specs) but it can be useful even without those."

The practical consequence: adding `@spec` to a `defp` does **not** give Dialyzer
new information it lacked. Dialyzer already knows the helper's actual type from
its body and its call sites. A private spec can only do one of three things:

1. **Restate** what Dialyzer already inferred — no new checking, pure redundancy.
2. **Narrow** the inferred type (an "underspec") — this can catch a caller that
   passes something the spec forbids, but Dialyzer flags underspecs only when you
   opt in (`flags: [:underspecs]` / `-Wunderspecs`), and a narrower-than-reality
   private spec is just as likely to generate false-positive noise you then have
   to suppress with `@dialyzer {:nowarn_function, ...}`.
3. **Contradict** the body (an "overspec"/wrong spec) — now the spec is a *new
   source of Dialyzer errors* that would not exist without it.

By contrast, a spec on a **public** `def` is doing work the inference cannot: it
constrains the *contract other modules rely on*, so Dialyzer can check external
callers against the promised type rather than against whatever the current body
happens to infer. That asymmetry — public specs constrain a real boundary,
private specs mostly restate an inference — is why the practice below skews so
hard toward public-only.

## What popular libraries do in practice (measured)

I measured the vendored `deps/` directly: for every `@spec` attribute, I
classified the function it decorates as `def` (public) or `defp` (private) by
walking each `.ex` file's AST-adjacent line structure (a spec, plus any
continuation/`@doc`/blank lines, immediately followed by a `def`/`defp`).

| Library | specs on `def` | specs on `defp` | total `defp` in lib | % of `defp` specced |
|---|---:|---:|---:|---:|
| `deps/phoenix` | 73 | 9 | 824 | ~1.1% |
| `deps/ecto` | 133 | 3 | 1584 | ~0.2% |
| `deps/plug` | 79 | 0 | 511 | 0% |
| `deps/phoenix_live_view` | 7 | 0 | 1288 | 0% |
| `deps/decimal` | 45 | 0 | 210 | 0% |
| `deps/req` | 68 | 0 | 253 | 0% |
| `deps/credo` | 5 | 0 | 1754 | 0% |
| `deps/dialyxir` | 206 | 6 | 134 | ~4.5% |

Across these eight libraries, **616 specs sit on public `def`s and only 18 on
private `defp`s** — about **97% of specs are on the public API**, and the
libraries collectively leave the overwhelming majority of their thousands of
private helpers unspecced. Plug, Phoenix LiveView, Decimal, Req, and Credo spec
**zero** private functions.

The handful of private specs that *do* exist reinforce the rule rather than
breaking it — they're almost all a specific special case: **private raise-helpers
annotated `:: no_return()`**, where the spec documents control flow (this helper
never returns) rather than adding type checking. From `deps/phoenix`:

```elixir
# deps/phoenix/lib/phoenix/controller.ex:520
@spec raise_invalid_url(term()) :: no_return()
defp raise_invalid_url(url) do
```
```elixir
# deps/phoenix/lib/mix/tasks/phx.gen.secret.ex:32
@spec invalid_args!() :: no_return()
defp invalid_args! do
```

The `phx.gen.auth/injector.ex` module is the closest thing to an exception —
it specs a cluster of private string-manipulation helpers
(`ensure_not_already_injected/2`, `split_with_self/2`,
`normalize_line_endings_to_file/2`, `get_line_ending/1`, all around
`deps/phoenix/lib/mix/tasks/phx.gen.auth/injector.ex:282`+). That one code
generator treats its private helpers like a documented internal API; it is the
outlier, not the pattern. Ecto's three private specs are similar one-offs
(`deps/ecto/lib/ecto/uuid.ex:348`, `deps/ecto/lib/ecto/query/builder.ex:1634`
and `:1652`).

`deps/dialyxir` is the only library with a meaningful private-spec density
(~4.5%), which is unsurprising: it is a tool *about* types, so its authors spec
more aggressively than a typical application would. Even there, public specs
outnumber private ones more than 30-to-1.

## What the community / style guides say

- **Credo ships the strongest normative signal, and it's installed here.** The
  `Credo.Check.Readability.Specs` check (`deps/credo/lib/credo/check/readability/specs.ex`)
  is the check that enforces "functions need typespecs." Its default is
  **`param_defaults: [include_defp: false]`** — out of the box Credo wants specs
  on public functions/callbacks/macros and **does not** ask for them on private
  functions; specing `defp` is an explicit opt-in (`include_defp: true`). The
  check is also tagged `:controversial`, i.e. Credo does not even turn it on by
  default. So the ecosystem's most-used linter encodes exactly "public API only"
  as its notion of complete spec coverage.

- **The official docs' documentation angle.** ExDoc emits nothing for `defp`
  (private functions are not part of the published docs; see the
  [Writing Documentation guide](https://elixir.hexdocs.pm/writing-documentation.html)),
  so a private spec is never user-facing documentation — removing half of the
  Typespecs guide's stated rationale when applied to `defp`.

- **Elixir Forum** threads on the topic
  ([What is the idiomatic way to use `@spec`?](https://elixirforum.com/t/what-is-the-idiomatic-way-to-use-spec/22946),
  [Dialyzer and private function causing an error](https://elixirforum.com/t/dialyzer-and-private-function-causing-an-error-what-am-i-missing/41556))
  debate *how* to spell multi-clause specs and note that private specs are a
  common *source* of Dialyzer errors — but treat specing the public API as the
  default and private specs as an optional, occasionally-troublesome extra. The
  recurring practical warning is that a wrong private spec creates Dialyzer noise
  that then has to be silenced with `@dialyzer {:nowarn_function, ...}`.

## Synthesis / recommendation

**Spec the public API; do not routinely spec private functions.** This matches
the official docs' rationale (private specs are neither documentation nor new
information for Dialyzer), the measured practice of Phoenix/Ecto/Plug/LiveView/
Decimal/Req/Credo (~97% of specs on `def`, most `defp`s unspecced), and Credo's
default (`include_defp: false`).

Proposed wording for `CODING_STANDARDS.md` (and cross-linkable from
`docs/moduledoc-style.md`):

> Put `@spec` on **public functions** (`def`) — they are the module's contract,
> the only functions Dialyzer can check *external* callers against, and the only
> ones ExDoc renders. **Do not** add `@spec` to private functions (`defp`) as a
> matter of course: Dialyzer already infers a success typing for every private
> helper, so a `defp` spec adds no checking it doesn't already do and can instead
> introduce false-positive Dialyzer warnings you then have to suppress. This
> mirrors Credo's `Readability.Specs` default (`include_defp: false`).
>
> Two narrow exceptions, both drawn from how the core libraries actually use
> private specs: (1) annotate a private **raise-helper** with
> `@spec name(...) :: no_return()` when it documents that the helper never
> returns; (2) spec a private helper when you *specifically* want Dialyzer to
> enforce a narrower contract than it would infer — and accept that you own any
> resulting `:nowarn_function` suppressions.

If we later enable `Credo.Check.Readability.Specs`, keep its `include_defp`
default (`false`) so the linter enforces the same public-only boundary described
here.
