LocalCents is an open-source expense-tracking application built with Phoenix LiveView and Tauri.

## Project guidelines

- See [`CODING_STANDARDS.md`](CODING_STANDARDS.md) for the index of how we write code here (moduledocs, `@impl`/`@spec` style, Bond components, boundaries, PubSub, commits); it links each rule's authoritative home
- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- When writing or editing a `@moduledoc`/`@typedoc`, follow the house standard in `docs/moduledoc-style.md` (summary-first line, explain the _why_, link ADRs rather than restate them, and calibrate length to the module's kind)
- When writing code comments, follow `docs/comment-style.md`: inline comments carry durable _why_ and never restate the signature; post single-use, reviewer-facing rationale as a PR review comment before review rather than baking it into the source; future-work asides become GitHub issues

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `LocalCentsWeb.Layouts` module is aliased in the `local_cents_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/local_cents_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


## Tauri and Rust

LocalCents uses [Tauri v2](https://tauri.app/) to package the Phoenix LiveView app as a cross-platform desktop application. Tauri acts as a thin native shell: it spawns the Elixir/Phoenix server as a child process and opens a WebView window pointed at `http://127.0.0.1:4000`.

### Directory layout

All Rust/Tauri code lives under `tauri/`:

| Path | Purpose |
|---|---|
| `tauri/src/lib.rs` | Main Tauri setup — spawns Elixir, subscribes to PubSub, creates the window |
| `tauri/src/main.rs` | Binary entry point — calls `local_cents_lib::run()` |
| `tauri/Cargo.toml` | Rust crate manifest (`local-cents` package / `local_cents_lib` lib) |
| `tauri/tauri.conf.json` | Tauri configuration (app identity, bundle targets, before-build command) |

### How it works

1. Rust creates an `elixirkit::PubSub` listener on a random TCP port.
2. Rust spawns the Elixir process (see dev vs. release below), passing the PubSub URL via the `ELIXIRKIT_PUBSUB` environment variable.
3. Once Phoenix is ready, Elixir sends `"ready"` on the `"messages"` PubSub channel.
4. Rust responds by calling `create_window()`, which opens a `WebviewWindowBuilder` pointed at `http://127.0.0.1:4000`.

The UI is entirely Phoenix LiveView — Tauri contributes no UI of its own beyond the native window chrome.

### ElixirKit

`elixirkit` is a local Rust library at `deps/elixirkit/elixirkit_rs`. It provides two things:

- **`PubSub`** — a TCP-based pub/sub bridge. Rust listens; Elixir connects and sends messages. This is the only IPC channel between Rust and Elixir.
- **Helper functions** — `elixirkit::mix(task, args)` builds a `mix` command, and `elixirkit::release(dir, name)` builds a command for running an Elixir release binary.

Do **not** add a separate IPC mechanism (e.g., Tauri commands, custom TCP sockets) without a strong reason — the PubSub bridge is the intended extension point.

### Dev vs. Release

`elixir_command()` in `tauri/src/lib.rs` chooses the Elixir invocation based on build mode:

- **Debug (`cargo tauri dev`)** — runs `mix phx.server` from the project root (one directory above `tauri/`). Phoenix hot-reloads normally.
- **Release (`cargo tauri build`)** — runs the pre-built Elixir release from the app bundle's resource directory (`tauri/target/rel`). The before-build command in `tauri.conf.json` compiles assets and generates the release:
  ```
  MIX_ENV=prod mix do compile + assets.deploy + release --overwrite --path tauri/target/rel
  ```
  Environment variables injected for the release: `PHX_SERVER=true`, `PHX_HOST=127.0.0.1`, `PORT=4000`.

### Rust guidelines

- Run `cargo tauri dev` (not `cargo run`) to develop the desktop app — this also starts the Tauri dev server and asset watcher.
- Run `cargo tauri build` to produce the release app bundle. Output lands in `tauri/target/release/bundle/`.
- The Rust crate's lib name is `local_cents_lib` (note the `_lib` suffix — required to avoid a Windows linker conflict with the binary name).
- Keep Rust logic minimal. Business logic belongs in Elixir; Rust is responsible only for native window management and process lifecycle.
- Do **not** add Tauri commands (`#[tauri::command]`) for data work that can be done in Phoenix/LiveView.
- The `SECRET_KEY_BASE` in `lib.rs` is a hardcoded placeholder suitable only for local desktop use — it is not a production web deployment.

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
