---
paths:
  - "tauri/**"
  - "native/**"
---

# Tauri and Rust

LocalCents uses [Tauri v2](https://tauri.app/) to package the Phoenix LiveView app as a cross-platform desktop application. Tauri acts as a thin native shell: it spawns the Elixir/Phoenix server as a child process and opens a WebView window pointed at `http://127.0.0.1:4000`.

Why the shell is shaped this way: [ADR 0006](../../docs/adr/0006-multi-window-desktop-shell.md).

## How it works

1. Rust creates an `elixirkit::PubSub` listener on a random TCP port.
2. Rust spawns the Elixir process (see dev vs. release below), passing the PubSub URL via the `ELIXIRKIT_PUBSUB` environment variable.
3. Once Phoenix is ready, Elixir sends `"ready"` on the `"messages"` PubSub channel.
4. Rust responds by calling `create_window()`, which opens a `WebviewWindowBuilder` pointed at `http://127.0.0.1:4000`.

The UI is entirely Phoenix LiveView — Tauri contributes no UI of its own beyond the native window chrome.

## ElixirKit

`elixirkit` is a local Rust library at `deps/elixirkit/elixirkit_rs`. It provides two things:

- **`PubSub`** — a TCP-based pub/sub bridge. Rust listens; Elixir connects and sends messages. This is the only IPC channel between Rust and Elixir.
- **Helper functions** — `elixirkit::mix(task, args)` builds a `mix` command, and `elixirkit::release(dir, name)` builds a command for running an Elixir release binary.

Do **not** add a separate IPC mechanism (e.g., Tauri commands, custom TCP sockets) without a strong reason — the PubSub bridge is the intended extension point.

## Dev vs. Release

`elixir_command()` in `tauri/src/lib.rs` chooses the Elixir invocation based on build mode:

- **Debug (`cargo tauri dev`)** — runs `mix phx.server` from the project root (one directory above `tauri/`). Phoenix hot-reloads normally.
- **Release (`cargo tauri build`)** — runs the pre-built Elixir release from the app bundle's resource directory (`tauri/target/rel`). The before-build command in `tauri.conf.json` compiles assets and generates the release:
  ```
  MIX_ENV=prod mix do compile + assets.deploy + release --overwrite --path tauri/target/rel
  ```
  Environment variables injected for the release: `PHX_SERVER=true`, `PHX_HOST=127.0.0.1`, `PORT=4000`.

## Rust guidelines

- Run `cargo tauri dev` (not `cargo run`) to develop the desktop app — this also starts the Tauri dev server and asset watcher.
- Run `cargo tauri build` to produce the release app bundle. Output lands in `tauri/target/release/bundle/`.
- The Rust crate's lib name is `local_cents_lib` (note the `_lib` suffix — required to avoid a Windows linker conflict with the binary name).
- Keep Rust logic minimal. Business logic belongs in Elixir; Rust is responsible only for native window management and process lifecycle.
- Do **not** add Tauri commands (`#[tauri::command]`) for data work that can be done in Phoenix/LiveView.
- The `SECRET_KEY_BASE` in `lib.rs` is a hardcoded placeholder suitable only for local desktop use — it is not a production web deployment.
- CI enforces Rust bumpers via the `Rust Quality` workflow (`.github/workflows/rust-quality.yaml`): `cargo fmt` (formatting), `cargo clippy -D warnings` (lints as hard failures), and `cargo test`, run against both `native/ex_automerge` and `tauri/`. Run `cargo fmt` and `cargo clippy --all-targets -- -D warnings` locally before pushing to match it.
