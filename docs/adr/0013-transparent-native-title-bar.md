# Transparent Title Bar

## Problem Statement

The desktop windows (library and document) should feel like the textured
`desktop_window` Storybook mock — paper grain running edge to edge, including up
into the title bar — while staying fully native macOS windows. The hardest
constraint is the green traffic-light button: its **Zoom** menu (Zoom / Enter
Full Screen / Tile Left/Right), double-click-to-zoom, and the Window ▸ Zoom menu
item are AppKit affordances with no web equivalent. Any approach that recreates
window controls in HTML loses them. How do we get the texture without giving up
native Zoom? (Follow-up from #61 and #93; traces to
[ADR 0006](0006-multi-window-desktop-shell.md).)

## Decision Made

Keep the native title bar but make it transparent, and paint our own marbled
endpaper bar (the `desktop_window` mock's dark-blue gradient) up into that region
with the title centered in white. The native traffic lights stay real and
functional, so native Zoom is preserved unchanged; they sit on the marble bar.

- **Rust** — `open_or_focus_window` in `tauri/src/lib.rs` builds every window with
  `title_bar_style(TitleBarStyle::Overlay)` + `hidden_title(true)`, cfg-gated to
  macOS (both builder methods are macOS-only; the shell is macOS-only for the MVP).
- **`Overlay`, not `Transparent`** — despite the issue framing this as the
  "transparent title bar" path, Tauri's `TitleBarStyle::Transparent` sets
  `titlebarAppearsTransparent` **without** `fullSizeContentView`, so the bar shows
  the window's background color rather than our HTML — our marble bar would not
  reach it. `Overlay` sets both, extending the content view under a transparent bar,
  which is what actually lets the `bond-marble` strip and a centered HTML title show
  through (verified against `tauri-runtime-wry`'s `title_bar_style` mapping). The
  native traffic lights and Zoom are untouched by either style.
- **HTML** — `Layouts.app` draws the `Bond.window_bar` component — a fixed-height
  (`h-7`) `bond-marble` strip — at the top of the paper `<main>`, marked
  `data-tauri-drag-region` so it drags the native window, with the window's title
  centered over it (`window_title`). Because the strip is a real flex child, the
  content below it is reserved clear of the traffic lights with no magic offsets. The
  native title text is hidden, so this HTML title is the only one shown; it is
  `aria-hidden` decorative chrome — each page keeps its own semantic heading.
- **Capability** — `data-tauri-drag-region` mousedown calls
  `__TAURI_INTERNALS__.invoke('plugin:window|start_dragging')`, so the webview needs
  `core:window:allow-start-dragging`. Crucially, the windows load a **remote origin**
  (`http://127.0.0.1:4000`, the Phoenix server), and Tauri v2 grants a capability's
  permissions to a remote origin only when the capability lists it under `remote.urls`
  — without that the drag IPC is silently rejected and the bar won't drag. The
  `default` capability now sets `remote.urls`, grants `allow-start-dragging`, and
  targets the real window labels (`library`, `book-*`) instead of the leftover `main`.

## Consequences & Tradeoffs

* **Considered and rejected: fully frameless (`decorations: false`).** It would
  match the mock pixel-for-pixel (faux traffic lights, fully custom bar) but loses
  the native traffic lights and forces reimplementing minimize / maximize / close in
  JS. Critically, `toggleMaximize()` cannot reproduce the green button's Zoom
  hover-menu, so it fails the native-Zoom requirement.
* **Accepted tradeoff:** with an overlay title bar the window cannot be dragged by
  the bar while it is unfocused (a known AppKit/tao limitation); clicking to focus
  first, then dragging, works normally.
* **Focus dimming:** the title dims in a background window to match macOS. The
  native traffic lights already dim via OS key-window state; `app.js` mirrors the
  WKWebView's window focus/blur to a `.window-inactive` class on `<html>` that
  `bond.css` keys the title off. (WebKit's CSS `:window-inactive` pseudo-class was
  tried first but did not apply to the title element in the WKWebView.)
* **Storybook:** the shipped `window_bar` reuses the mock's `bond-marble` styling,
  so the app matches the `desktop_window` catalog entry — the only difference is the
  real traffic lights replacing the faux ones (Storybook has no native chrome). The
  `desktop_window` component stays as a presentation-only mock of a whole window.
* Because the shell is macOS-only, the title-bar calls are cfg-gated; on other
  targets the windows fall back to a normal title bar and the HTML strip still
  renders (harmless, just not overlaid), keeping the deferred web mirror workable.
