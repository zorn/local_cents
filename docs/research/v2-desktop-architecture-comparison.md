# How v2 and LocalCents Run on macOS

> Research note prompted by a question comparing the macOS architecture of two local-first desktop apps: LocalCents and [oktana-coop/v2](https://github.com/oktana-coop/v2), a local-first rich-text editor built on Git, Automerge, ProseMirror, and Pandoc. No issue feeds it.
>
> Every v2 claim links to a file in the v2 repo, pinned to commit [`0ec8edd`](https://github.com/oktana-coop/v2/tree/0ec8edd1d944888569c7e586fd8a74896aad61d2). Every LocalCents claim links to a file or ADR on `main` in this repo.

## Summary

In v2 the webview *is* the app: the UI, the editor, and the Automerge document all run as JavaScript and WASM in an Electron renderer, and the main process is a wide service layer for the filesystem, Git, and native features. In LocalCents the webview is a thin LiveView client: a Tauri shell starts an embedded BEAM, and the BEAM holds the Automerge document, renders the UI on the server, and tells Rust which windows to open.

## How v2 runs

### Stack

v2 is an Electron 43 app built with electron-vite. Its UI uses React 18 and ProseMirror, and its domain code uses Effect-TS ([`package.json`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/package.json)). The app runs as the usual three Electron layers: a Node main process, a preload script, and a Chromium renderer.

### Main process

The main process owns everything that touches the operating system ([`src/main/index.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts)):

- **Filesystem.** A Node filesystem adapter and a directory watcher.
- **Git.** Project stores run on [isomorphic-git](https://github.com/oktana-coop/v2/tree/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/infrastructure/version-control/git-lib) and are registered through [`src/main/ipc/project-stores.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/ipc/project-stores.ts).
- **Pandoc.** Pandoc ships inside `v2-hs-lib`, a Haskell library compiled to WASM ([`AGENTS.md`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/AGENTS.md)). The main process runs it with Node's `node:wasi` ([`node-wasm/index.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/infrastructure/wasm/adapters/node-wasm/index.ts)). The WASM file is a prebuilt blob in the tree, so a source build needs no Haskell toolchain ([`docs/release.md`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/docs/release.md)).
- **PDF.** A paged.js engine ([`paged-js-pdf-engine`](https://github.com/oktana-coop/v2/tree/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/domain/rich-text/adapters/paged-js-pdf-engine)).
- **Credentials.** An encrypted store on Electron `safeStorage` ([`electron-main-encrypted-store.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/auth/adapters/electron-main-encrypted-store.ts)). On macOS `safeStorage` uses the Keychain, and v2 allows a plaintext fallback when no keyring exists ([`src/main/index.ts` L96-L99](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts#L96-L99)).
- **Menus and auto-update.** An application menu, context menus, and `electron-updater`, which is skipped on Linux ([`src/main/update.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/update.ts)).

The renderer reaches all of this over IPC. Across `src/main/` there are about 100 `ipcMain.handle` and `ipcMain.on` registrations, plus streamed change events served through a helper ([`src/main/ipc/project-store-changes.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/ipc/project-store-changes.ts)).

The app takes a single-instance lock, and a second launch focuses the existing window ([L104](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts#L104)). It opens one `BrowserWindow` with `titleBarStyle: 'hidden'` on macOS ([L139-L148](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts#L139-L148)). The window loads the Vite dev server in development and `dist/renderer/index.html` in production ([L150-L158](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts#L150-L158)). An `open-win` handler for child windows also exists, but nothing in `src/` calls it; it reads as leftover template code ([L335](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/main/index.ts#L335)).

### Preload

The preload script uses `contextBridge` to expose several typed APIs on `window`: `electronAPI`, `filesystemAPI`, `projectStoreAPI`, `authAPI`, `wasmAPI`, and others ([`src/preload/index.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/preload/index.ts)). Almost every method is an `ipcRenderer.invoke` call. A few use `send` or `on` for fire-and-forget messages and events.

### Renderer

The renderer holds the React UI, the ProseMirror editor, and Automerge. Automerge runs as WASM in the page ([`automerge-repo.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/infrastructure/sync/automerge-repo.ts)). The app keeps two `automerge-repo` instances ([`context.tsx`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/renderer/src/app-state/infrastructure-adapters/context.tsx)):

- A **private repo** with no network and no storage. Documents that are not shared live here, so they cannot reach the sync service.
- A **synced repo** with IndexedDB storage and a WebSocket client to a sync service. It is built lazily, so a client that never shares or joins a document never connects.

The default sync service is `wss://sync3.automerge.org` ([`.env.sample`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/.env.sample)).

### Storage

The durable store is not Automerge. A project is a folder of Markdown files, and Git is the default version control, so a project and a Git repo are one-to-one ([`AGENTS.md`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/AGENTS.md)). Automerge serves document sharing: a shared document is identified by an Automerge URL and synced through the synced repo ([`automerge-document-sharing`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/domain/project/adapters/automerge-document-sharing/index.ts)).

### Packaging

electron-builder builds macOS `dmg` and `zip` targets for `x64`, `arm64`, and `universal`. The mac build uses the hardened runtime, a notarization entitlements file, and a `.v2` file association ([`electron-builder.yml`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/electron-builder.yml)). The entitlements allow JIT, unsigned executable memory, and disabled library validation, plus network client access ([`entitlements.mac.plist`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/public/macos-notarization/entitlements.mac.plist)). Signing and notarization run during the build, with the Developer ID certificate and Apple credentials injected from CI secrets ([`docs/release.md`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/docs/release.md)). The same code also ships as a Windows NSIS installer and as Linux AppImage, `deb`, and `rpm` packages.

## How LocalCents runs

### Shell and process layout

A Tauri shell starts an Elixir release as a child process ([`tauri/src/lib.rs`](https://github.com/zorn/local_cents/blob/main/tauri/src/lib.rs)). The release is bundled as a Tauri resource from `target/rel` ([`tauri/tauri.conf.json`](https://github.com/zorn/local_cents/blob/main/tauri/tauri.conf.json)). In a debug build the shell runs `mix phx.server` instead. Phoenix serves on `127.0.0.1:4000`.

Each window is a WKWebView that loads an external URL: a LiveView route on that local server. All UI renders on the server through LiveView. On macOS the window uses an overlay title bar with a hidden native title ([ADR 0013](https://github.com/zorn/local_cents/blob/main/docs/adr/0013-transparent-native-title-bar.md)).

### Native bridge

Rust and Elixir share one channel: an `elixirkit` PubSub bridge over TCP on the `"messages"` topic, carrying JSON commands ([`tauri/src/lib.rs`](https://github.com/zorn/local_cents/blob/main/tauri/src/lib.rs), [`desktop_shell.ex`](https://github.com/zorn/local_cents/blob/main/lib/local_cents_web/desktop_shell.ex)). Elixir sends `open-window`, `close-window`, `set-title`, and `set-offline-menu`. Rust sends `toggle-offline` when the user clicks the Developer menu item. There is no `#[tauri::command]`, so the webview never calls Rust directly ([ADR 0006](https://github.com/zorn/local_cents/blob/main/docs/adr/0006-multi-window-desktop-shell.md)).

The shell stamps each webview's user agent with `LocalCents/<version> (desktop)`. The server uses that stamp to tell a native window from a browser tab, so one server serves both ([ADR 0023](https://github.com/zorn/local_cents/blob/main/docs/adr/0023-browser-as-a-second-client.md)).

### Windows

The app opens a library window at launch and one document window per Book. Opening a Book that is already open focuses its window ([ADR 0006](https://github.com/zorn/local_cents/blob/main/docs/adr/0006-multi-window-desktop-shell.md)). The MVP is macOS-only.

### State and storage

A per-Book `BookServer` GenServer holds the Book's Automerge document and is its single source of truth ([ADR 0007](https://github.com/zorn/local_cents/blob/main/docs/adr/0007-book-runtime-and-persistence.md)). The document lives in Rust through the `ex_automerge` Rustler NIF, which binds the `automerge` crate and `autosurgeon` ([ADR 0001](https://github.com/zorn/local_cents/blob/main/docs/adr/0001-which-automerge-rust-library.md), [`native/ex_automerge/Cargo.toml`](https://github.com/zorn/local_cents/blob/main/native/ex_automerge/Cargo.toml)). Each Book persists to a `.lcbook` file in the application-support directory, and the bytes are a standard Automerge document ([ADR 0009](https://github.com/zorn/local_cents/blob/main/docs/adr/0009-book-file-format.md)). There is no SQL store.

### Sync

Sync is BEAM to BEAM. Two peers exchange Automerge sync-protocol messages over a Phoenix Channel ([ADR 0025](https://github.com/zorn/local_cents/blob/main/docs/adr/0025-two-peer-sync-architecture.md)). The NIF exposes `new_sync_state`, `generate_sync_message`, and `receive_sync_message` ([`native/ex_automerge/src/lib.rs`](https://github.com/zorn/local_cents/blob/main/native/ex_automerge/src/lib.rs)). The peer connects on a dedicated socket, separate from the LiveView socket ([`peer_socket.ex`](https://github.com/zorn/local_cents/blob/main/lib/local_cents_web/peer_socket.ex)). A browser stays a thin LiveView client of whichever BEAM serves it.

## Side by side

| | v2 | LocalCents |
|---|---|---|
| Shell | Electron 43 (bundled Chromium + Node) | Tauri (system WKWebView) |
| Where logic and state live | Renderer (React, Automerge) plus a Node main process for OS services | Embedded BEAM; per-Book `BookServer` |
| UI rendering | Client side: React and ProseMirror in the renderer | Server side: LiveView over a local socket |
| Native bridge | About 100 IPC channels behind typed `contextBridge` APIs | One `elixirkit` PubSub topic; JSON window and menu commands |
| Automerge binding | `@automerge/automerge` WASM in the renderer, via `automerge-repo` | `automerge` crate in a Rustler NIF |
| Durable storage | Markdown files in a Git repo; IndexedDB for shared documents | One `.lcbook` Automerge file per Book |
| Sync | `automerge-repo` WebSocket client to a sync service | Automerge sync protocol between BEAMs over a Phoenix Channel |
| Windows | One main window | Library window plus one window per Book |
| Platforms | macOS, Windows, Linux | macOS only (MVP) |

## Observations

### v2 is the architecture ADR 0025 rejected

[ADR 0025](https://github.com/zorn/local_cents/blob/main/docs/adr/0025-two-peer-sync-architecture.md) rejected the browser as an independent JS/WASM Automerge peer. Its main cost was a client-side rendering path beside LiveView. v2 is that architecture, and the cost is natural for it. A rich-text editor needs ProseMirror in the page anyway, so the UI is already client-rendered before Automerge arrives. An expense form has no such need, so for LocalCents the cost buys only a browser that works with no server, which the product does not require.

### v2's IPC surface is wide because its webview has no server behind it

v2's renderer holds the document but cannot touch the disk, Git, or the Keychain. Every such operation crosses IPC, which is why the preload exposes so many methods. In LocalCents the BEAM does all data work and renders the UI, so the webview needs nothing from Rust. Rust only needs window and menu commands, and one PubSub topic carries them.

### v2 gets Automerge networking and storage for free in JS

`automerge-repo` gives v2 a WebSocket network adapter, an IndexedDB storage adapter, and Automerge URLs as share IDs, in a few lines ([`automerge-repo.ts`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/src/modules/infrastructure/sync/automerge-repo.ts)). Rust repo layers exist (`automerge-repo-rs` and `samod`), but LocalCents chose not to adopt them and let Elixir own the repo responsibilities ([ADR 0001](https://github.com/zorn/local_cents/blob/main/docs/adr/0001-which-automerge-rust-library.md)). [ADR 0025](https://github.com/zorn/local_cents/blob/main/docs/adr/0025-two-peer-sync-architecture.md) also notes that there is no mature, JS-compatible Rust `automerge-repo` for the BEAM to meet. That is why LocalCents builds its own layer on the raw sync protocol.

### v2's packaging is a reference for distribution

LocalCents is not yet set up for distribution. Its bundle identifier is still `com.example.LocalCents` ([`tauri.conf.json`](https://github.com/zorn/local_cents/blob/main/tauri/tauri.conf.json)), and the release build hardcodes port 4000 and a `SECRET_KEY_BASE` with a FIXME ([`tauri/src/lib.rs`](https://github.com/zorn/local_cents/blob/main/tauri/src/lib.rs)). When LocalCents reaches distribution, v2's setup is a working example of the macOS pieces: hardened runtime, notarization entitlements, universal builds, CI-injected signing credentials, and a file association ([`electron-builder.yml`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/electron-builder.yml), [`docs/release.md`](https://github.com/oktana-coop/v2/blob/0ec8edd1d944888569c7e586fd8a74896aad61d2/docs/release.md)). The exact entitlements LocalCents needs are unverified, since its bundle carries a BEAM release and a NIF rather than Chromium, but the pipeline shape carries over. The `.v2` association also parallels the deferred `.lcbook` UTI registration in [ADR 0009](https://github.com/zorn/local_cents/blob/main/docs/adr/0009-book-file-format.md).
