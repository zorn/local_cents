# Browser As A Second Client

## Problem Statement

LocalCents ships as a Tauri desktop app: Rust spawns Phoenix, opens native windows, and
each window loads a LiveView route ([ADR 0006](0006-multi-window-desktop-shell.md)). But
the server it spawns is an ordinary Phoenix server on `127.0.0.1:4000`, and in day-to-day
development it is convenient to launch the app with `cargo tauri dev` and then drive it
from a browser tab beside the native window.

That only half worked. `LocalCentsWeb.DesktopShell` publishes window commands
fire-and-forget over the `ElixirKit.PubSub` bridge, so with no native shell listening,
**Open** in a browser silently did nothing — the one action the library exists for. There
was no way back to the library from a Book page, because on the desktop a Book *is* its
own window and needs none. And `/` still served `HomeLive`, a counter left over from
wiring up the bridge, which the native app never loads.

The underlying issue is that the app had one client baked in as an assumption. Several
screens encode "the shell will do this for me," and nothing in the code could tell
whether that was true for the request in hand.

## Decision Made

**The browser is a supported second client, and every view knows which one it is
rendering into.**

Views read a `@client` assign, either `:desktop` or `:browser`. It is assigned by
`LocalCentsWeb.Client.on_mount/4`, attached once in `LocalCentsWeb.live_view/0` — the same
place the ADR 0019 `handle_info` fallback is injected — because unlike
`LocalCentsWeb.BookWindow`, which encodes a contract only the document-window views rely
on, every view renders into a client.

**The signal is the user agent.** `open_or_focus_window` in `tauri/src/lib.rs` — which
every native window is built through — stamps the webview with
`LocalCents/<version> (desktop)`. `LocalCentsWeb.Plugs.Client` classifies each request and
puts the result in the session; the mount hook reads it from there. A request without the
token is a browser: the desktop is the case that has to announce itself.

The session, rather than connect params, is what makes this correct on the **disconnected
first render** as well as the connected mount — a native window never paints browser
chrome for a beat and then corrects itself.

What changes between the two clients:

- **Open**, in the library, is a `<.link navigate={...}>` styled as the same button rather
  than a `phx-click` that asks for a window. Because it is a real link, cmd-click and
  middle-click give a Book its own tab — the browser's own answer to the desktop's several
  windows at once.
- **Creating a Book** navigates to it. On the desktop, creating opens a window *and* the
  library stays put; a single tab cannot have both halves, and going to the Book you just
  named is the more useful one.
- **The title strip** (`Bond.Layouts.WindowBar`) drops `data-tauri-drag-region`, which is
  inert in a browser, and the leading space reserved for the native traffic lights
  ([ADR 0013](0013-transparent-native-title-bar.md)) carries a back link instead. That is
  the *window-level* way out and is distinct from the in-page "‹ Expenses" link the
  secondary views already draw; on those pages the two read as a breadcrumb.
- **A debug bar** — a collapsed pill that expands into Storybook, Docs, and LiveDashboard
  links — appears when the client is a browser *and* the `:dev_routes` flag is on. It is
  gated on the same flag that guards LiveDashboard so the bar and its targets appear and
  disappear together. ExDoc's output is served by a dev-only `Plug.Static` at `/doc`.

**The Docs link goes through a gateway, not straight at `doc/index.html`.** That directory
is a gitignored build artifact, so "show me the docs" has three honest answers, not one:
they are current, they are behind the source, or they were never built.
`LocalCentsWeb.DevDocsLive` at `/dev/docs` picks between them. Current — much the
commonest — redirects straight through, so the link costs nothing; the other two render a
short panel that says which it is and offers the button that fixes it, running `mix docs`
in a subprocess off the LiveView process. Staleness is decided by comparing
`doc/index.html`'s modification time against the sources ExDoc reads, which is advisory
rather than exact: touching a file without changing it counts, and the only cost of being
wrong is a rebuild nobody needed.

`HomeLive` is deleted and `/` redirects to `/library`, keeping one canonical URL for the
library. `LocalCentsWeb.ConnCase` and `LocalCentsWeb.FeatureCase` stamp the desktop user
agent on the conn they build, so the suite tests the primary client by default and browser
tests opt in with `browser_conn/1`.

This **refines** ADR 0006 rather than replacing it. The desktop is still the product, and
the multi-window model is unchanged; this only says what the same routes do when no native
shell is listening.

## Consequences & Tradeoffs

* **Considered:** detecting the client from a JS connect param (`window.__TAURI__`, which
  is available since `withGlobalTauri` is on). Rejected — connect params only exist once
  the socket connects, so the disconnected render would have to guess, and a native window
  would flash browser chrome before correcting itself.
* **Considered:** inferring the client from the route (`/` means browser, `/library` means
  native). Rejected — `/books/:id` is the same route in both clients, so the document
  views, which need the distinction most, would stay blind.
* **Considered:** naming the concept `shell`. Rejected — `shell` already means the
  imperative shell of [ADR 0014](0014-functional-core-process-shell.md) *and* the Tauri
  container. `host` collides with `conn.host`/`PHX_HOST`, `runtime` with the Book runtime,
  and `viewer` with `BookServer` viewers. `client` was free.
* **Accepted:** `WebviewWindowBuilder::user_agent` *replaces* the webview's user agent
  rather than appending to it, so native windows no longer report a WebKit UA. Nothing in
  the app sniffs the user agent except `LocalCentsWeb.Client`, and there is no third-party
  JS, so the blast radius is small — but server logs are less informative about the
  webview, and anything added later that cares about browser capabilities would be misled.
* **Accepted:** the token is a cross-language contract. Changing the string in
  `tauri/src/lib.rs` without changing `@desktop_token` in `LocalCentsWeb.Client` silently
  turns every native window into a browser. A Rust unit test asserts the prefix, and the
  Elixir side keeps the token in one place, the way `DesktopShell` keeps the window-command
  wire format.
* **Accepted:** views now branch on `@client`, and `Layouts.app` takes it as a *required*
  attr so a view that forgets fails `compile --warnings-as-errors` rather than quietly
  rendering the wrong chrome. Each new branch is a place the two clients can drift.
* **Accepted:** the debug bar is gated at compile time, so it never renders in the test
  environment and is covered by its Storybook story rather than a test — matching how the
  rest of Bond is covered. `LocalCentsWeb.DevDocsLive` is behind the same gate and so is
  likewise untested; the staleness logic it rests on lives in `LocalCentsWeb.DevDocs`,
  which is tested against a fixture project directory.
* **Considered:** letting the Docs link 404 when `doc/` has never been generated, on the
  grounds that `mix precommit` runs `mix docs` and so any working checkout has them.
  Rejected — it is exactly the fresh-clone case where a dead end is least welcome, and the
  same gateway that fixes it also catches the commoner problem of docs that exist but are
  behind the source, which a direct link would serve silently and wrongly.
* **Accepted:** the docs gateway shells out to `mix`. That is fine in a dev checkout and
  meaningless in a release, which is why nothing routes to it outside `:dev_routes`.
* **Accepted:** once the docs are current the gateway redirects, so the rebuild button is
  unreachable. That is the intent — there is nothing to rebuild — but it does mean there is
  no way to force a regeneration from the UI.
* **Easier:** a hosted LocalCents, should it ever exist, now has a client to be. The
  browser path is exercised every day rather than discovered later.
