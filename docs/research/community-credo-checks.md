# Community Credo check libraries

> Research note behind a possible tooling decision: beyond `jump_credo_checks`
> (already installed), which **third-party Credo check collections** published on
> Hex/GitHub should LocalCents consider adding? Every library below was confirmed
> against **primary sources** — its Hex.pm package page and its GitHub
> repo/`mix.exs` — for existence, latest version, release/commit recency, Credo
> `~> 1.7` compatibility, and license. Blog posts and forum threads were used only
> to *locate* these packages, never as authorities. Anything that could not be
> confirmed on Hex or GitHub is called out and excluded.

## Question

The project already runs the full stock Credo check set (`strict: true`) plus the
enabled Jump.CredoChecks. Are there other actively-maintained community check
collections worth enabling alongside them — particularly ones that match this
stack (Phoenix LiveView, Ecto, ExUnit/PhoenixTest, general Elixir quality) — and
where do they overlap or conflict with what is already enabled so we don't
double-enable equivalent rules?

Context that shaped the verdicts:

- Installed floor is `{:credo, "~> 1.7"}`, deps are `only: [:dev, :test], runtime: false`.
- `mix.exs` declares `elixir: "~> 1.15"`, but the dev/CI toolchain actually runs
  **Elixir 1.20.1 / OTP 28** (`.tool-versions`). That gap matters: two candidates
  below require `elixir ~> 1.18` in their own `mix.exs`, which compiles fine on the
  current toolchain but would raise the effective floor for anyone building the
  dev tooling on the declared `~> 1.15`.
- The project uses **no Mox/Hammox** and **no Ash** (`mix.exs`), which rules out
  two otherwise-real check libs.

## `credo_naming` — naming & file/module-name consistency

- Real. Package: [hex.pm/packages/credo_naming](https://hex.pm/packages/credo_naming),
  **v2.1.0, last updated Nov 21 2023**, license **BSD-3-Clause**.
- The old `pepicrft/credo_naming` URL 404s; the canonical repo is
  [mirego/credo_naming](https://github.com/mirego/credo_naming) (the Hex "Links"
  point there). `mix.exs` on `master` requires `{:credo, "~> 1.6"}` and
  `elixir: "~> 1.8"`, so it is **compatible with Credo `~> 1.7`**
  ([mix.exs](https://raw.githubusercontent.com/mirego/credo_naming/master/mix.exs)).
- Provides two checks
  ([mirego/credo_naming README](https://github.com/mirego/credo_naming)):
  - `CredoNaming.Check.Warning.AvoidSpecificTermsInModuleNames` — flags configured
    terms (e.g. `Manager`, `Helper`/`Helpers`) in module names.
  - `CredoNaming.Check.Consistency.ModuleFilename` — enforces that a module's name
    matches its file path, with acronym handling and a Phoenix-aware plugin.
- **Overlap:** none with stock Credo or the Jump checks — neither ships a
  file↔module-name consistency check. `ModuleFilename` would overlap with Nicene's
  `FileAndModuleName` (see below), but Nicene is stale so that is moot.
- **Verdict: strong candidate.** Stable, correct license, Credo `~> 1.7`-clean, and
  `ModuleFilename` is a low-noise, high-value guard for a LiveView app with many
  `LocalCentsWeb.*` modules. No release since 2023, but the check surface is tiny
  and stable — "quiet, not abandoned." Adopt `ModuleFilename`; treat
  `AvoidSpecificTermsInModuleNames` as optional/opinionated.

## `excellent_migrations` — Ecto migration safety

- Real. [artur-sulej/excellent_migrations](https://github.com/artur-sulej/excellent_migrations),
  package `excellent_migrations` **v0.1.10**, license **MIT**, ~330k recent
  downloads ([Hex dependents listing](https://hex.pm/packages/credo/dependents)).
  Repo is actively maintained (145 commits, 295 stars).
- `mix.exs` declares `{:credo, "~> 1.5", optional: true}` and `elixir: ">= 1.11.0"`
  ([mix.exs](https://raw.githubusercontent.com/artur-sulej/excellent_migrations/master/mix.exs)),
  so it is **compatible with Credo `~> 1.7`**. It ships **both** a standalone mix
  task (`mix excellent_migrations.check_safety`) **and** a ready-to-use Credo check,
  so it can plug straight into `.credo.exs`.
- Detects ~13 unsafe-migration patterns: removing/renaming columns or tables,
  adding a column with a default, adding FKs/references, changing column types,
  setting `NOT NULL`, adding check constraints, backfilling data in a migration,
  raw SQL, non-`concurrently` index creation, volatile defaults, Postgres JSON
  columns, and multi-column-index best practice
  ([README](https://github.com/artur-sulej/excellent_migrations)).
- **Overlap:** none. Nothing in stock Credo or the Jump checks reasons about Ecto
  migrations.
- **Verdict: does not apply — skip.** An earlier draft of this note called it a
  "strong candidate" on the assumption that LocalCents is Ecto-backed. That is
  **wrong**: LocalCents depends on `{:ecto, "~> 3.14"}` for embedded
  schemas/changesets only — there is **no `ecto_sql`, no `Repo`, and no
  database** (see [ADR 0016](../adr/0016-ecto-embedded-validation-no-repo.md) and
  the `mix.exs` deps comment), and consequently **no `priv/repo/migrations/`
  directory**. This check scans `priv/repo/migrations/*.exs`; with zero migration
  files it has nothing to analyze and would contribute no findings. Separately,
  its value proposition is *zero-downtime production-database* safety, which does
  not apply to a single-user local desktop store even if migrations existed.
  **Do not adopt.**

## `ex_slop` — checks for AI-generated "code slop"

- Real. [elixir-vibe/ex_slop](https://github.com/elixir-vibe/ex_slop),
  package [hex.pm/packages/ex_slop](https://hex.pm/packages/ex_slop) **v0.4.3,
  released Jul 17 2026**, license **MIT** — very active (last release days before
  this note).
- `mix.exs` requires `{:credo, "~> 1.7"}` and **`elixir: "~> 1.18"`**
  (verified via `gh api` on `main`). Credo-compatible; the Elixir `~> 1.18` floor is
  fine on the current 1.20.1 toolchain but exceeds the project's declared `~> 1.15`.
- Ships ~40 checks across Warning / Refactor / Readability, including several tuned
  to this stack ([README](https://github.com/elixir-vibe/ex_slop)):
  `BlanketRescue`, `RescueWithoutReraise`, `RepoAllThenFilter` (Ecto: fetch-all then
  filter in Elixir), `QueryInEnumMap` (N+1-shaped), `GenserverAsKvStore`,
  plus readability nits like `NarratorDoc`, `ObviousComment`, `StepComment`,
  `DocFalseOnPublicFunction`.
- **Overlap:** meaningful with stock Credo `Refactor.*` and `Readability.*` — e.g.
  its Enum-chain and boolean-`if` refactors cover ground stock Credo already
  touches (`Refactor.FilterFilter`, `Refactor.NegatedConditionsInUnless`, etc.), and
  its comment/doc checks overlap the project's own `docs/comment-style.md` posture.
  Some conceptual overlap with `forge_credo_checks` below (both target LLM output).
- **Verdict: worth considering.** LocalCents is AI-assisted, so slop-catching checks
  are on-target, and `RepoAllThenFilter`/`QueryInEnumMap`/`BlanketRescue` are
  genuinely useful here. But it is a large, opinionated, months-old surface with
  real overlap against the stock set, and it raises the Elixir floor. If adopted,
  cherry-pick the Ecto/rescue Warning checks and disable the comment/doc opinions
  rather than enabling the whole collection.

## `forge_credo_checks` — LLM anti-pattern checks

- Real. [BobbieBarker/forge_credo_checks](https://github.com/BobbieBarker/forge_credo_checks),
  package [hex.pm/packages/forge_credo_checks](https://hex.pm/packages/forge_credo_checks)
  **v0.8.0, released Jul 15 2026**, license **MIT**. Active.
- `mix.exs` requires `{:credo, "~> 1.7"}` and **`elixir: "~> 1.18"`**
  ([mix.exs](https://raw.githubusercontent.com/BobbieBarker/forge_credo_checks/main/mix.exs)).
  Credo-compatible; same `~> 1.18` floor caveat as `ex_slop`.
- Targets "anti-patterns LLMs commonly generate: wasteful Enum chains, with-macro
  misuse, broad typespecs, inline regex, telemetry control flow, unsupervised
  spawns" ([Hex description](https://hex.pm/packages/forge_credo_checks)).
- **Overlap:** conceptually redundant with `ex_slop` (both are LLM-slop collections;
  overlapping Enum-chain and typespec themes) and its Enum-chain checks overlap stock
  `Refactor.*`.
- **Verdict: worth considering — but pick one AI-slop library, not both.** It is the
  smaller, more focused of the two LLM-slop collections. Evaluate it head-to-head
  with `ex_slop`; do not enable both.

## `oeditus_credo` — 40 Phoenix/Ecto/security anti-pattern checks

- Real. [Oeditus/oeditus_credo](https://github.com/Oeditus/oeditus_credo),
  package `oeditus_credo` **v0.8.1, released Jun 29 2026**, license **MIT**
  ([Hex dependents listing](https://hex.pm/packages/credo/dependents)). Actively
  developed.
- `mix.exs` requires `{:credo, "~> 1.7"}` and `elixir: "~> 1.14"`
  ([mix.exs](https://raw.githubusercontent.com/Oeditus/oeditus_credo/main/mix.exs)) —
  **fully compatible** with both the Credo floor and the declared Elixir `~> 1.15`.
- 40 checks ([README](https://github.com/Oeditus/oeditus_credo)) spanning:
  Ecto/perf (`NPlusOneQuery`, `MissingPreload`, `InefficientFilter`), LiveView/
  concurrency (`UnmanagedTask`, `MissingHandleAsync`, `MissingThrottle`,
  `InlineJavascript`, `SyncOverAsync`), error handling (`MissingErrorHandling`,
  `SwallowingException`), and an 11-check **security** group (`SQLInjection`,
  `XSSVulnerability`, `HardcodedCredentials`, `MissingAuthorization`, …).
- **Overlap/conflict:** the security group overlaps the domain of **Sobelow**
  (Phoenix security scanner) more than Credo; the LiveView `InlineJavascript` check
  overlaps the project's own CLAUDE.md rule forbidding inline `<script>`. These are
  heuristic, higher-false-positive checks — many are "risk anti-pattern" advisories,
  not deterministic rules.
- **Verdict: worth considering, cherry-pick only — but not the Ecto checks.**
  Note the same no-database caveat that rules out `excellent_migrations`:
  `NPlusOneQuery`, `MissingPreload`, and `InefficientFilter` all reason about
  `Ecto.Repo` query patterns, and LocalCents has no `Repo` (ADR 0016), so they
  would never fire. The interesting checks here are instead the **LiveView/
  concurrency** ones (`UnmanagedTask`, `MissingHandleAsync`, `SyncOverAsync`,
  `InlineJavascript`) — this is the best-maintained/Credo-cleanest of the big
  collections. But enabling all 40 under `strict: true` would be noisy and would
  drift Credo into security-scanner territory. Do **not** adopt wholesale; trial a
  couple of the LiveView checks in isolation.

## Nicene — stale, do not adopt

- Real but **stale**. [sketch-hq/nicene](https://github.com/sketch-hq/nicene)
  (owner is **sketch-hq**, not the "Rosa/estheruary" guessed in the brief; that could
  not be confirmed and is excluded). Package
  [hex.pm/packages/nicene](https://hex.pm/packages/nicene) **v0.7.0, released
  Sep 20 2022**, license MIT.
- **Last commit Sep 20 2022**, 12 open issues, docs still reference **Credo 1.6.1**
  ([commits](https://github.com/sketch-hq/nicene/commits),
  [README](https://nicene.hexdocs.pm/readme.html)); no verified `~> 1.7` support.
- Checks include `Nicene.FileAndModuleName` (overlaps `credo_naming`'s
  `ModuleFilename`), `Nicene.UnnecessaryPatternMatching`, `Nicene.FileTopToBottom`.
- **Verdict: skip.** Nearly four years without a commit and pinned to Credo 1.6-era
  docs. Its one distinctive value (file↔module naming) is better served by the
  maintained `credo_naming`.

## `credo_contrib` — abandoned, do not adopt

- Real but **abandoned**. [hex.pm/packages/credo_contrib](https://hex.pm/packages/credo_contrib)
  **v0.2.0, released Aug 10 2019**, license ISC. No release in ~7 years; no verified
  Credo `~> 1.7` support.
- **Verdict: skip** (stale). Its style-guide checks are largely subsumed by the
  modern stock Credo set.

## Not Credo check collections (classified and excluded)

- **`recode`** — [hrzndhrn/recode](https://github.com/hrzndhrn/recode), v0.8.0
  (Oct 10 2025), MIT, actively maintained. **Not a Credo plugin**: its own README
  states it "was started as a plugin for credo" but autocorrection was impossible
  because "Credo's traversal of the code does not support changing the code," so it
  is a **standalone linter/refactoring tool** (depends on `sourceror`, not Credo).
  Out of scope for "Credo check collections." Could be evaluated separately as an
  autocorrecting linter, but it does **not** slot into `.credo.exs`.
- **`ex_check`** — [hex.pm/packages/ex_check](https://hex.pm/packages/ex_check),
  v0.16.0 (Mar 1 2024), MIT. **An aggregate runner** ("one task to run all code
  analysis & testing tools"), not a check collection — it orchestrates Credo,
  Dialyzer, formatter, tests, etc. Misclassifying it as a check lib would be wrong.
  Out of scope (though it's a legitimate CI convenience tool).
- **`quokka`** (v2.13.1) and **`ex_dna`** (v1.5.4) surfaced in the Credo dependents
  list ([listing](https://hex.pm/packages/credo/dependents)): `quokka` is a
  Credo-configured **style auto-fixer** (Styler-family), `ex_dna` is a **duplication
  detector**. Adjacent tooling, not check collections to enable alongside the Jump
  checks. Out of scope.
- **`credo_mox`** (v0.1.3, Apache-2.0) — real, but provides Mox/Hammox checks and
  the project uses **neither**. Not applicable.
- **`ash_credo`** (v0.17.0) — real, but Ash-framework-specific; the project does
  **not** use Ash. Not applicable.

## Recommendation

| Library | Maintained? | Credo `~>1.7`? | Relevant checks | Overlap | Verdict |
|---|---|---|---|---|---|
| ~~excellent_migrations~~ | Yes (active) | Yes (`~>1.5`, optional) | Ecto migration safety (~13 patterns) | None | **Skip** — no `ecto_sql`/`Repo`/migrations here (ADR 0016) |
| **credo_naming** | Stable (last rel. 2023) | Yes (`~>1.6`) | `ModuleFilename` file↔module consistency | vs. stale Nicene only | **Adopt** `ModuleFilename` |
| oeditus_credo | Yes (very active) | Yes (`~>1.7`) | `NPlusOneQuery`, `MissingPreload`, some LiveView | Security dup. of Sobelow; noisy | Consider — cherry-pick 2–4 checks |
| ex_slop | Yes (very active) | Yes (`~>1.7`, elixir `~>1.18`) | `RepoAllThenFilter`, `BlanketRescue`, `QueryInEnumMap` | vs. stock `Refactor/Readability`; vs. forge | Consider — cherry-pick; raises Elixir floor |
| forge_credo_checks | Yes (active) | Yes (`~>1.7`, elixir `~>1.18`) | LLM anti-patterns (Enum chains, with-misuse) | vs. ex_slop (redundant) | Consider — pick one AI-slop lib, not both |
| nicene | No (Sep 2022) | Unverified (1.6-era) | file/module naming | vs. credo_naming | Skip (stale) |
| credo_contrib | No (2019) | Unverified | style-guide checks | vs. stock Credo | Skip (abandoned) |
| recode | Yes | N/A (not a plugin) | autocorrecting linter | — | Out of scope (separate tool) |
| ex_check | Yes | N/A (runner) | orchestrates tools | — | Out of scope (CI runner) |
| credo_mox | Yes | — | Mox/Hammox | — | N/A (no Mox) |
| ash_credo | Yes | — | Ash | — | N/A (no Ash) |

**Top picks for LocalCents:**

1. **`credo_naming` (`ModuleFilename`)** — cheap, low-noise consistency guard for the
   many `LocalCents.*` / `LocalCentsWeb.*` modules; fills a gap neither stock Credo
   nor the Jump checks cover.

> **Note:** an earlier draft ranked `excellent_migrations` as the top pick. It has
> been demoted to **skip** — LocalCents has no `ecto_sql`, no `Repo`, and no
> migrations (Ecto is used for embedded validation only, per
> [ADR 0016](../adr/0016-ecto-embedded-validation-no-repo.md)), so a
> migration-safety linter has nothing to analyze. See its section above.

**Second tier (trial individual checks, never enable wholesale):**
`oeditus_credo`'s LiveView/concurrency checks (e.g. `UnmanagedTask`,
`MissingHandleAsync`, `SyncOverAsync`) — **not** its Ecto checks, which need a
`Repo` this project doesn't have — and **one** of the AI-slop libs (`ex_slop` or
`forge_credo_checks`) for a project that ships AI-assisted code, with the caveat
that both AI-slop libs pin `elixir ~> 1.18`, above the project's declared `~> 1.15`
floor (fine on the current 1.20.1 toolchain).

**Skip:** `excellent_migrations` (no `ecto_sql`/`Repo`/migrations — ADR 0016);
`nicene`, `credo_contrib` (both unmaintained); `recode`, `ex_check`, `quokka`,
`ex_dna` (not Credo check collections); `credo_mox`, `ash_credo` (dependencies the
project doesn't use).
