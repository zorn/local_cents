# CI Checks Used by Popular Elixir Projects

> Research note (2026-07-18) surveying the CI setups of well-known, actively-maintained Elixir open-source projects, to help decide which additional automated checks LocalCents should adopt.
> Every claim below links to a **primary source**: the project's real `.github/workflows/*.yml` file on GitHub, its `mix.exs`, or the tool's official repo/hexdocs. No blog-post summaries were used as evidence. Workflow links point at each repo's default branch; contents were read on 2026-07-18.
>
> **Update (2026-07-18):** Every **Adopt**-rated recommendation here shipped in [PR #144](https://github.com/zorn/local_cents/pull/144). See [Implementation status](#implementation-status) for what was adopted, what already existed, and what was deferred — plus a couple of factual corrections the implementation surfaced.

## Bottom line for the maintainer

LocalCents already runs a **stronger-than-average** static-analysis gate: compile-warnings-as-errors, `deps.unlock --check-unused`, format, Credo `--strict`, Dialyzer, Sobelow, and an `xref` compile-connected check. Most surveyed projects run a *subset* of that. The genuinely common checks LocalCents is **missing** are small, cheap, and security/hygiene-flavored rather than heavyweight: a **known-CVE dependency scan** (`mix deps.audit` / mix_audit), a **lockfile-integrity flag** (`mix deps.get --check-locked`), **`mix test --warnings-as-errors`**, **Dependabot for GitHub Actions/Cargo**, and **actionlint** on the workflow YAML itself. None of these add meaningful CI time or flakiness. The higher-cost checks the big libraries run — multi-version Elixir/OTP **matrix testing**, **ExCoveralls uploads**, doc-coverage (`mix doctor`) — earn their keep for a *published Hex library* but pay back poorly for a **single-maintainer desktop app** that ships one bundled runtime and has no external API consumers.

---

## Prioritized recommendations

> The "LocalCents today" column reflects the state at survey time (2026-07-18, before [#144](https://github.com/zorn/local_cents/pull/144)). For current state, see [Implementation status](#implementation-status).

| Check | Command / tool | Who uses it (sources below) | LocalCents today | Rec |
|---|---|---|---|---|
| Known-CVE dep scan | `mix deps.audit` ([mix_audit](https://github.com/mirego/mix_audit)) | Ash | No | **Adopt** — near-zero cost, catches CVEs in the transitive tree Sobelow doesn't. |
| Lockfile integrity | `mix deps.get --check-locked` | Req, Plug, Broadway | No | **Adopt** — one line; fails if `mix.lock` would change, i.e. someone forgot to commit it. |
| Test-time warnings | `mix test --warnings-as-errors` | Req, Explorer, Finch, LiveView, Ash | Only *compile* WAE | **Adopt** — one flag; also surfaces Elixir 1.18+ set-theoretic type warnings on test-only paths. |
| Action/dep freshness | Dependabot (`github-actions`, `cargo`) | Phoenix, Oban, Ash | No | **Adopt** — keeps pinned actions + Rust crates patched; the mix side is already handled by the repo's dep-update skill. |
| Workflow-YAML lint | [actionlint](https://github.com/rhysd/actionlint) | (ecosystem tool; not in surveyed core repos) | No | **Adopt** — the repo has 4 workflows + a tricky composite/caching action; actionlint is a single fast binary. |
| Retired-package check | `mix hex.audit` | Ash (audit job) | No | **Consider** — cheap, but low signal until a dep is actually retired. |
| Docs build guard | `mix docs` (warnings) | ex_doc, LiveView, Ash | No | **Consider** — the repo already publishes ex_doc collections and has fixed doc-link warnings by hand; a build gate prevents regressions. |
| Test coverage | ExCoveralls / `mix test --cover` | Credo, Broadway, Tesla, Membrane; LiveView (built-in) | No | **Consider** — use built-in `mix test --cover`, no external upload; skip a hard threshold gate for a solo project. |
| Async flake / slow tests | `--slowest N`, `--repeat-until-failure`, `--trace` | Req, Tesla | No | **Consider** — `--repeat-until-failure` is a good *ad-hoc* tool given the Rust NIF + async; not a standing gate. |
| Multi-version matrix | Elixir/OTP matrix + "lint leg" | ~every library surveyed | Single pinned version | **Consider (narrow)** — a desktop app bundles one runtime; at most add a single "next Elixir/OTP" lane before upgrading. |
| Formatter rewriter | [Styler](https://github.com/adobe/elixir-styler) | (ecosystem; not in surveyed core repos) | No | **Consider** — big one-time diff; overlaps existing Credo `--strict`. |
| Doc coverage | `mix doctor` | Ash | No | **Skip** — the repo's moduledoc standard + review already cover this; `--raise` is noisy. |
| Conventional-commit lint | `git_ops` / commit-msg lint | Ash | Yes *(PR-title lint)* | **Skip** — already covered by the PR-title lint. |
| Migrations / schema drift | `ecto.migrations` / `*.generate_migrations --check` | Ecto, Ash | n/a | **Skip** — LocalCents has no Ecto/SQL database (state is Automerge files). |
| License-header compliance | REUSE | Ash | No | **Skip** — niche; matters for multi-file-licensed libraries, not a solo app. |

---

## Per-check findings

### Matrix testing across Elixir/OTP versions (+ the "lint leg" pattern)

This is the single most universal pattern in the surveyed projects, and it comes bundled with a convention worth understanding: **run tests on many Elixir/OTP pairs, but run the lint/static checks only once, on the newest pair**, gated by an `if: ${{ matrix.lint }}` flag.

- Phoenix runs a 3-pair `include` matrix (Elixir 1.15/1.18/1.19 against OTP 25/27/28) and marks only the newest `lint: true` — [`ci.yml`](https://github.com/phoenixframework/phoenix/blob/main/.github/workflows/ci.yml).
- Ecto runs a 5-pair matrix down to Elixir 1.14 / OTP 24, one leg flagged `lint` — [`ci.yml`](https://github.com/elixir-ecto/ecto/blob/master/.github/workflows/ci.yml).
- Oban, Req, Finch, Plug, Broadway, Tesla, Bandit, ex_doc, LiveView all follow the same "matrix + single lint leg" shape — e.g. [Oban `ci.yml`](https://github.com/oban-bg/oban/blob/main/.github/workflows/ci.yml), [Req `ci.yml`](https://github.com/wojtekmach/req/blob/main/.github/workflows/ci.yml), [Finch `elixir.yml`](https://github.com/sneako/finch/blob/main/.github/workflows/elixir.yml), [Plug `ci.yml`](https://github.com/elixir-plug/plug/blob/main/.github/workflows/ci.yml), [Broadway `ci.yml`](https://github.com/dashbitco/broadway/blob/main/.github/workflows/ci.yml).
- Credo tests a full cross-product of OTP 25–29 x Elixir 1.16–1.20 with an explicit `exclude` list for incompatible pairs — [`ci-workflow.yml`](https://github.com/rrrene/credo/blob/master/.github/workflows/ci-workflow.yml).
- Version selection is via [`erlef/setup-beam`](https://github.com/erlef/setup-beam) with explicit `elixir-version`/`otp-version` in the matrix (LocalCents uses the same action but pins a single version through `.tool-versions` + `version-type: strict`).

**Value:** libraries *must* support a range of runtimes because their users run many. **Cost:** N× the CI minutes and cache storage.
**LocalCents:** already covered as *single-version*. LocalCents is a **desktop app that bundles exactly one Elixir/OTP runtime** in the Tauri release, so the "our users run old Elixir" motivation does not apply. **Recommendation: Consider (narrow).** The only useful variant is a *single extra lane* on the next Elixir/OTP before doing an upgrade — not a standing multi-version matrix.

### `mix test --warnings-as-errors`

LocalCents runs `mix compile --warnings-as-errors` but runs `mix test` plain. Compiling with WAE does **not** catch warnings raised while compiling *test* modules or warnings emitted at test time; `mix test --warnings-as-errors` does.

- Req: `mix test.all --slowest 5 --warnings-as-errors` on the lint leg — [`ci.yml`](https://github.com/wojtekmach/req/blob/main/.github/workflows/ci.yml).
- Explorer: `mix test --warnings-as-errors` (and again for `--only property`) — [`ci.yml`](https://github.com/elixir-explorer/explorer/blob/main/.github/workflows/ci.yml).
- Finch: `mix test --warnings-as-errors` on the lint leg — [`elixir.yml`](https://github.com/sneako/finch/blob/main/.github/workflows/elixir.yml).
- Phoenix LiveView: `mix test --cover --export-coverage default --warnings-as-errors` — [`ci.yml`](https://github.com/phoenixframework/phoenix_live_view/blob/main/.github/workflows/ci.yml).

The flag is documented in [`mix test`](https://hexdocs.pm/mix/Mix.Tasks.Test.html). Note that in Elixir 1.18+ the compiler's new [gradual set-theoretic types](https://hexdocs.pm/elixir/gradual-set-theoretic-types.html) surface as ordinary compile warnings, so WAE on both `compile` and `test` is how projects "gate on" the new type system today — there is no separate `mix` task for it.
**Recommendation: Adopt.** One flag on the existing `mix test` step; zero new tooling.

### `--slowest`, `--trace`, `--repeat-until-failure` (slow tests & async flake)

- Req passes `--slowest 5` to print the five slowest tests every run — [`ci.yml`](https://github.com/wojtekmach/req/blob/main/.github/workflows/ci.yml).
- Tesla runs `mix test --trace` (serial, per-test output) — [`test.yml`](https://github.com/elixir-tesla/tesla/blob/master/.github/workflows/test.yml).
- `--repeat-until-failure N` (added in Elixir 1.17) reruns the suite until a test fails, the standard way to smoke out order-dependent/async flakes — [`mix test` docs](https://hexdocs.pm/mix/Mix.Tasks.Test.html).

**Recommendation: Consider.** `--slowest 5` is a free, always-on nicety. `--repeat-until-failure` is best as an *ad-hoc local* tool (worth remembering because of the Rust NIF + async surface), not a standing CI gate where it would multiply run time.

### Retry-on-flake conventions

Two distinct approaches appear, both aimed at incremental-build / transient flakiness:

- Oban re-runs failed tests inline: `mix test ... || mix test --failed` — [`ci.yml`](https://github.com/oban-bg/oban/blob/main/.github/workflows/ci.yml).
- Bandit re-dispatches the *whole workflow* up to 5 attempts on failure via a `re-run` job — [`elixir.yml`](https://github.com/mtrudel/bandit/blob/main/.github/workflows/elixir.yml).

**LocalCents:** already has the most surgical version of this — the `elixir-setup` composite action does a full `mix clean` **only on retried runs** (`github.run_attempt != '1'`), which is exactly the "rule out incremental build as a source of flakiness" idea. **No change needed.**

### Lockfile integrity — `mix deps.get --check-locked`

Separate from LocalCents' existing `mix deps.unlock --check-unused` (which flags *unused* entries), `--check-locked` fails if resolving deps would *modify* `mix.lock` — i.e. someone bumped a dep in `mix.exs` but didn't commit the resulting lockfile.

- Req: `mix deps.get --check-locked` — [`ci.yml`](https://github.com/wojtekmach/req/blob/main/.github/workflows/ci.yml).
- Plug: dedicated "Ensure mix.lock is up to date" step running `mix deps.get --check-locked` — [`ci.yml`](https://github.com/elixir-plug/plug/blob/main/.github/workflows/ci.yml).
- Broadway: `mix do deps.get --check-locked, deps.compile` — [`ci.yml`](https://github.com/dashbitco/broadway/blob/main/.github/workflows/ci.yml).

**Recommendation: Adopt.** Add `--check-locked` to the deps-install step in the `elixir-setup` action (or a dedicated step). One line, no flakiness.

### Dependency security & freshness

**Known-CVE scanning — `mix deps.audit` (mix_audit).** This is the biggest genuine gap. Sobelow scans *your* Phoenix code for insecure patterns; it does **not** cross-reference your dependency versions against a vulnerability database. mix_audit does: it matches every `mix.lock` entry against the community [elixir-security-advisories](https://github.com/mirego/mix_audit#how-does-it-work) feed and exits non-zero on a match — [mirego/mix_audit](https://github.com/mirego/mix_audit), [hexdocs](https://hexdocs.pm/mix_audit).

- Ash runs it in a dedicated `audit` job (`task: deps.audit`, via the `team-alembic/staple-actions` wrapper) — [`ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml).

Add as `{:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}` and run `mix deps.audit` in the quality workflow. **Recommendation: Adopt** — highest security ROI of anything on this list.

**Retired packages — `mix hex.audit`.** Ships with Hex; flags deps that upstream has *retired* (deprecated/insecure/renamed) — [hexdocs](https://hexdocs.pm/hex/Mix.Tasks.Hex.Audit.html). Ash includes it in its audit job. **Recommendation: Consider** — free to add alongside `deps.audit`, but low day-to-day signal.

**Dependabot.** Phoenix and Oban both keep a `.github/dependabot.yml`; Phoenix covers `github-actions` + `npm`, Oban covers `mix` + `github-actions` (grouped) — [Phoenix `dependabot.yml`](https://github.com/phoenixframework/phoenix/blob/main/.github/dependabot.yml), [Oban `dependabot.yml`](https://github.com/oban-bg/oban/blob/main/.github/dependabot.yml); [Dependabot docs](https://docs.github.com/en/code-security/dependabot). LocalCents pins several actions (some already to SHAs) and has a `cargo` crate tree under `native/ex_automerge`. **Recommendation: Adopt for `github-actions` and `cargo`.** The **mix** ecosystem is already handled by the repo's dedicated dep-update skill, so leaving `mix` out of Dependabot avoids duplicate PRs.

> **Correction (2026-07-18):** the survey's "LocalCents today: No" for Dependabot was inaccurate — a `.github/dependabot.yml` already existed covering `mix`, `cargo`, and `github-actions`. And the mix-exclusion advice was **not** taken: the maintainer prefers to keep the `mix` entry as a monthly outdated-deps nudge (a useful signal even when the actual update runs through the skill). The only change made was removing the broken `cargo` `/tauri` entry — see [Implementation status](#implementation-status).

### Test coverage — ExCoveralls vs. built-in `mix test --cover`

Two camps:

- **ExCoveralls with an upload.** Broadway runs `mix coveralls.github` on its coverage leg — [`ci.yml`](https://github.com/dashbitco/broadway/blob/main/.github/workflows/ci.yml). Credo, Tesla, and Membrane also depend on `excoveralls` (confirmed in their `mix.exs`). Tool: [parroty/excoveralls](https://github.com/parroty/excoveralls) / [hexdocs](https://hexdocs.pm/excoveralls). ExCoveralls supports minimum-coverage thresholds and Coveralls/Codecov uploads.
- **Built-in, no dependency.** Phoenix LiveView uses Elixir's native `mix test --cover --export-coverage default` and aggregates with `mix test.coverage` — [`ci.yml`](https://github.com/phoenixframework/phoenix_live_view/blob/main/.github/workflows/ci.yml). This needs **no** extra dep and no third-party upload.

**Value:** visibility into untested code. **Cost/friction:** a hard threshold gate is a recurring source of "unblock my PR" friction, and third-party uploads (Coveralls/Codecov) add a token + external dependency.
**Recommendation: Consider — built-in only.** For a solo project, `mix test --cover` for *local visibility* is worth it; skip the external upload and skip a failing threshold gate until there's a second contributor to hold accountable.

> **Correction (2026-07-21):** [issue #154](https://github.com/zorn/local_cents/issues/154)
> adopted **`excoveralls`** for local visibility rather than the built-in tool
> this survey leaned toward — the line-by-line `mix coveralls.html` report is the
> thing that makes "eyeball what's untested" worth repeating, and the survey's two
> objections don't bite the *local* case: there is **no threshold gate** and **no
> external upload**. Both remain live concerns for the *CI* question, which is
> deliberately deferred to [issue #155](https://github.com/zorn/local_cents/issues/155)
> and blocked on #154. How coverage is run and why it stays local:
> [`docs/testing-coverage.md`](../testing-coverage.md).

### Documentation checks

- **Docs build guard.** ex_doc, LiveView, and Ash all build docs in CI (ex_doc's `test/prerelease.sh`, LiveView's `docs.yml`, Ash's `mix docs` job) — [ex_doc `ci.yml`](https://github.com/elixir-lang/ex_doc/blob/main/.github/workflows/ci.yml), [Ash `ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml). Running `mix docs` in CI catches broken cross-references and doc-link warnings. LocalCents already publishes ex_doc collections and recently fixed doc-link warnings *by hand* (see the repo's own recent doc commits), so a build gate would prevent that regressing. **Recommendation: Consider/Adopt** — add a `mix docs` step (optionally with warnings treated as failures).
- **Doc coverage — `mix doctor`.** Ash runs `mix doctor --full --raise`, which fails when modules/functions lack `@moduledoc`/`@doc`/`@spec` — [`ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml); tool: [akoutmos/doctor](https://github.com/akoutmos/doctor). **Recommendation: Skip.** LocalCents already enforces a moduledoc *style* standard through code review and its `@spec`/`@impl` conventions; `doctor --raise` tends to be noisy for an app (vs. a library with a public API) and would fight the project's deliberate choices about which internals get docs.

### Formatting beyond `mix format`

- Every surveyed project runs `mix format --check-formatted` (LocalCents already does).
- **Styler** ([adobe/elixir-styler](https://github.com/adobe/elixir-styler)) is a `mix format` *plugin* that auto-rewrites code (sorts aliases, rewrites deprecated stdlib calls, auto-fixes many Credo rules). It's widely adopted ecosystem-wide but did **not** appear in the surveyed *core-library* repos' configs. **Recommendation: Consider.** It produces a large one-time diff and overlaps rules LocalCents already gets from Credo `--strict`; adopt only if the maintainer wants aggressive auto-normalization.

### Credo custom checks

LocalCents already runs `mix credo --strict` with a sizable project `.credo.exs`. Notable extra usage seen elsewhere:

- Ash also emits **Credo results as SARIF** and uploads them to GitHub code-scanning (`credo --format sarif` -> `upload-sarif`) — [`ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml). Nice for the Security tab, but redundant when the CI already fails on Credo. **Skip** unless the maintainer wants findings surfaced in GitHub's Security UI.

### Type checking — Dialyzer vs. set-theoretic types

- **Dialyzer** is run by Oban, Bandit, Finch, Tesla, and Ash — with a shared best practice of caching the PLT keyed on OTP+Elixir version. Bandit's reusable lint workflow even **auto-evicts a stale PLT cache and retries** when Dialyzer fails — [mtrudel/elixir-ci-actions `lint.yml`](https://github.com/mtrudel/elixir-ci-actions/blob/main/.github/workflows/lint.yml). LocalCents already runs Dialyzer with PLT caching and `--format github`; its cache-eviction story is manual, so Bandit's auto-evict-and-retry is a **possible refinement** if PLT staleness ever bites.
- **Set-theoretic types (Elixir 1.17/1.18+):** there is no separate CI task — the compiler emits type warnings during `mix compile`, so `--warnings-as-errors` (already in place, plus the recommended `mix test --warnings-as-errors`) is the gate. [Docs](https://hexdocs.pm/elixir/gradual-set-theoretic-types.html).
- **Gradient** exists as an alternative gradual type-checker but was **not** found in any surveyed project's CI; not recommended.

**LocalCents:** type checking is already well covered.

### `mix xref` (compile-time deps / deprecations)

LocalCents already runs `mix xref graph --label compile-connected --fail-above 0`, which is **more** than the surveyed libraries put in CI — none of the read workflows ran an `xref` gate. This is a LocalCents strength; keep it. **No change.**

### GitHub Actions / YAML / shell linting

- **actionlint** ([rhysd/actionlint](https://github.com/rhysd/actionlint)) statically checks workflow YAML (expression syntax, `runs-on` labels, shell issues via shellcheck, matrix typos). It's an ecosystem-standard tool but did **not** appear in the surveyed Elixir *core* repos' workflows — those tend to hand-maintain simpler YAML. LocalCents has 4 workflows plus a non-trivial composite action with layered caching keyed on Rust source hashes, which is exactly the kind of YAML where a typo silently disables a cache. **Recommendation: Adopt** — runs as a single fast binary/action, no Elixir toolchain needed.
- **yamllint / shellcheck** standalone: marginal once actionlint (which embeds shellcheck for `run:` blocks) is present. **Skip.**

### Migrations / schema drift (Ecto)

Ecto's own suite and Ash both guard migrations (Ash runs `*.generate_migrations --check` and `ecto.migrate` in CI — [`ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml)). **Not applicable to LocalCents:** its persistent state is Automerge `.lcbook` files via the Rust NIF, not an Ecto/SQL schema. **Skip.**

### Conventional commits / changelog / license headers

- **Conventional commit lint:** Ash runs `mix git_ops.check_message` — [`ash-ci.yml`](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml) ([git_ops](https://github.com/ash-project/git_ops)). **LocalCents already enforces conventional-commit style at the PR-title level** (`lint-pr.yaml`), which fits a squash-merge flow better than per-commit linting. **Skip.**
- **Changelog enforcement:** Ash's `changelog-lint` and Membrane's `enforce-changelog-update.yml` require CHANGELOG updates — [Membrane workflows](https://github.com/membraneframework/membrane_core/tree/master/.github/workflows). Relevant only if LocalCents keeps a user-facing CHANGELOG; **Skip** for now.
- **REUSE license compliance:** Ash checks per-file SPDX headers. Niche to multi-license libraries. **Skip.**

### Precommit hooks conventions

The projects surveyed rely on **CI as the enforcement point** rather than shipping git hooks. LocalCents' own `mix precommit` alias (compile-WAE, deps.unlock, format, credo, dialyzer, sobelow, test) is a *local* convenience mirroring CI — consistent with the ecosystem norm (e.g. Phoenix's generated apps also ship a `precommit` alias). If the recommended checks are adopted, add the cheap ones (`deps.audit`, `deps.get --check-locked`, `test --warnings-as-errors`) to the `precommit` alias too so they're catchable before push.

---

## Suggested next steps (highest value, lowest friction first)

Status markers added 2026-07-18 after [PR #144](https://github.com/zorn/local_cents/pull/144). ✅ done · ➖ already present · ⏸ deferred.

1. ✅ **Add `mix deps.audit` (mix_audit)** to the Code Quality workflow and the `precommit` alias — the one real security gap; catches CVEs in the dependency tree that Sobelow can't see.
2. ✅ **Add `--check-locked` to `mix deps.get`** in the `elixir-setup` action — one flag; guarantees `mix.lock` is committed and consistent.
3. ✅ **Add `--warnings-as-errors` to the `mix test` step** — one flag; extends the existing warnings gate to test code and to Elixir 1.18+ type warnings.
4. ➖ **Add a Dependabot config** for `github-actions` and `cargo` — already existed (see the correction under [Dependency security & freshness](#dependency-security--freshness)). The maintainer opted to **keep** the `mix` entry as a monthly nudge rather than leave it to the dep-update skill; the broken `/tauri` cargo entry was removed.
5. ✅ **Add actionlint** as its own tiny job — done, using the official `rhysd/actionlint` image; supply-chain hardening deferred to [#145](https://github.com/zorn/local_cents/issues/145).
6. ➖/⏸ *(Optional, when convenient)* The **`mix docs` build guard** already exists (Lint job + `precommit`) and the **PLT anti-staleness** rebuild-on-retry already exists in `dialyzer.yaml`; local-only **`mix test --cover`** is deferred.

Everything below step 5 is a "nice to have"; steps 1–3 are a few lines total and could ride in a single PR.

---

## Implementation status

> Recorded 2026-07-18. Adopted in [#144](https://github.com/zorn/local_cents/pull/144); follow-up tracked in [#145](https://github.com/zorn/local_cents/issues/145).

Everything the survey rated **Adopt** shipped in a single PR, along with a couple of structural changes and dependency bumps that fell out of the work.

**Adopted (new)**

- **`mix deps.audit` (mix_audit)** — added as a dev/test dep, a step in the new **Security** CI job, and to the `precommit` alias. Wiring it up immediately surfaced three vulnerable transitive deps, bumped to patched releases: `mint` 1.9.3, `phoenix_live_view` 1.2.7, `plug` 1.20.3. Worth noting for the future: Hex's own `mix deps.get` advisory scan (EEF/osv.dev feed) caught these, while `mix deps.audit` (mirego feed) had not yet listed them — the two feeds are complementary, not redundant.
- **`mix deps.get --check-locked`** — added to the deps-install step in the `elixir-setup` composite action.
- **`mix test --warnings-as-errors`** — added to the CI test step and the `precommit` alias.
- **actionlint** — added as its own `Actionlint` workflow using the official first-party `rhysd/actionlint` image (bundles shellcheck). The mutable-tag / container-privilege supply-chain surface is tracked for hardening in [#145](https://github.com/zorn/local_cents/issues/145).

**Already present (no change needed)**

- **Dependabot** — a `.github/dependabot.yml` already covered `mix`, `cargo` (workspace root `/` = the `native/ex_automerge` NIF), and `github-actions`, all monthly + grouped. The `cargo` `/tauri` entry was **removed**: `tauri/Cargo.toml` has a path dependency on `../deps/elixirkit/elixirkit_rs`, which resolves into the gitignored Mix `deps/` directory, so Dependabot errored on every run ("couldn't fetch all your path-based dependencies") — an `ignore` can't help, since it only suppresses update PRs, not the earlier fetch step.
- **`mix docs` build guard** — already ran with `--warnings-as-errors` in CI (now in the **Lint** job) and in `precommit`.
- **Dialyzer PLT anti-staleness** — `dialyzer.yaml` already force-rebuilds the PLT on retried runs (`github.run_attempt != '1'`), covering the Bandit-style eviction idea; the fully-automatic in-run variant remains a future refinement only if staleness actually bites.

**Deliberately deferred**

- **`mix test --cover`** (local visibility, no threshold gate) — not adopted for now.
- Multi-version matrix, ExCoveralls upload, Styler, `mix doctor`, Credo SARIF upload, etc. — remain **Consider/Skip** as originally assessed.

**Structural change**

- The single `quality_checks` CI job was split into two — **Lint** (format, Credo, unused deps, xref, docs) and **Security** (Sobelow, `deps.audit`) — so a PR reports them as distinct, independently-failing status lines. This was motivated by the job having accumulated enough checks that a single red ❌ was hard to diagnose.
