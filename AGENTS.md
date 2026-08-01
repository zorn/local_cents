LocalCents is an open-source expense-tracking application built with Phoenix LiveView, Automerge and Tauri.

## Project guidelines

- **Before writing or editing code, read [`CODING_STANDARDS.md`](CODING_STANDARDS.md).** It is the index of how we write code here — moduledocs, comments, `@impl`/`@spec` style, Bond components, testing, boundaries, PubSub, commits — and links each rule's authoritative home. Read it up front rather than discovering a convention at review time
- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Branch each PR from an up-to-date `main`, not from whatever is currently checked out — `git switch main && git pull` then `git switch -c <name>`. Branching off another feature branch stacks them, so the new PR inherits the other's commits and its diff shows unrelated files. This bites especially when several agents share one working directory: confirm you are on `main` before creating a branch
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Area-specific conventions

Conventions that only matter for one part of the tree live in `.claude/rules/`
and load automatically when Claude reads a matching file, so they stay out of
every unrelated session:

| Rule file | Loads when working on |
|---|---|
| `.claude/rules/phoenix-liveview.md` | `lib/local_cents_web/`, `test/local_cents_web/` |
| `.claude/rules/js-css.md` | `assets/`, `storybook/`, the web layer |
| `.claude/rules/rust-tauri.md` | `tauri/`, `native/` |

Because they load on read, a session that creates a brand-new file may not have
seen them yet — open the matching rule directly when starting greenfield work in
an area.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (`zorn/local_cents`) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default triage vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`CONTEXT.md` glossary + `docs/adr/` at the repo root). See `docs/agents/domain.md`.

<!-- usage-rules-start -->
<!-- igniter-start -->
## igniter usage
_A code generation and project patching framework_

[igniter usage rules](deps/igniter/usage-rules.md)
<!-- igniter-end -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- phoenix:elixir-start -->
## phoenix:elixir usage
[phoenix:elixir usage rules](deps/phoenix/usage-rules/elixir.md)
<!-- phoenix:elixir-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
