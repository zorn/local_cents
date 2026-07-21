# Test Coverage

Test coverage in LocalCents is a **local, exploratory tool** — a way to eyeball,
on demand, which parts of the code the suite never exercises. It is deliberately
**not** wired into `mix precommit` or CI, and there is no threshold gate. Run it
when you want the visibility; ignore it the rest of the time.

## Running a report

Coverage is provided by [`excoveralls`](https://hexdocs.pm/excoveralls), a
`:test`-only dependency. The task you'll usually want is the browsable HTML
report:

```
mix coveralls.html
```

That writes `cover/excoveralls.html` — every source file rendered with each line
tinted green (covered) or red (uncovered), so you can scan a module and see the
exact untested branches. The `cover/` directory is gitignored.

Two lighter variants exist for a quick look without leaving the terminal:

```
mix coveralls          # a per-file percentage summary table
mix coveralls.detail   # the same, plus colorized line-by-line source
```

All three run the full test suite under `MIX_ENV=test` (the `cli/0`
`preferred_envs` in [`mix.exs`](../mix.exs) selects that env for you).

The only configuration is [`coveralls.json`](../coveralls.json), which skips the
`storybook/` stories. Those are compiled modules the test suite never renders,
so they read as 0% and — being numerous — drag the headline total well below the
real `lib/` figure; skipping them keeps `[TOTAL]` honest. There is deliberately
**no** `minimum_coverage` threshold and no upload service: coverage stays a local
eyeball tool, not a gate.

## Why it's exploratory, not a gate

Coverage data is genuinely useful for one thing: spotting **whole areas** of
untested behavior. It is much less useful — and actively harmful — as a
pass/fail gate, for reasons specific to how we test here.

A percentage gate rewards writing tests to move the number, and the cheapest way
to move it is to test implementation details. That is exactly the kind of
low-value, high-upkeep test our
[testing strategy](research/testing-strategy-public-api-vs-internals.md) steers
away from: we favor tests against a context's public API (`LocalCents.Tracking`)
over its internals, because those survive refactors and the internal-detail
tests do not. A coverage ratchet pushes in the opposite direction.

CI coverage adds its own failure modes on top — run-to-run wobble, misattributed
per-PR deltas, and the token/supply-chain surface of a third-party upload
service. Whether any of that is worth inducing on ourselves is a separate
decision, tracked in
[issue #155](https://github.com/zorn/local_cents/issues/155) and blocked on this
tooling landing first. Until that decision is made, coverage stays a thing you
reach for locally, not a thing that can fail a build.
