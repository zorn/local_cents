use serde::Deserialize;
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem, SubmenuBuilder};
use tauri::Manager;

// The Phoenix endpoint every window loads from; window commands carry only the
// route path and Rust prepends this host (see ADR 0006).
const BASE_URL: &str = "http://127.0.0.1:4000";

// The Developer > offline-mode menu item. A demo-only control that suspends the sync
// link so the two peers diverge on cue (ADR 0025). Its title flips between the two
// actions rather than carrying a checkmark, per the Apple HIG rule for a feature
// toggle. The app always starts online, so the resting title offers "Enable".
const OFFLINE_MENU_ID: &str = "toggle-offline";
const ENABLE_OFFLINE_TEXT: &str = "Enable Offline Mode";
const DISABLE_OFFLINE_TEXT: &str = "Disable Offline Mode";

// Window cascade: the first window opens at CASCADE_ORIGIN and each subsequent
// window steps CASCADE_STEP down-and-right, so windows never stack exactly.
const CASCADE_ORIGIN: f64 = 120.0;
const CASCADE_STEP: f64 = 28.0;

// Default and minimum window size. Below the minimum the library's create bar
// (field + Cancel + Create) and book rows start to overflow, so the native
// window refuses to shrink past it — the first line of defense against a
// too-small window breaking the layout.
const DEFAULT_WIDTH: f64 = 800.0;
const DEFAULT_HEIGHT: f64 = 600.0;
const MIN_WIDTH: f64 = 520.0;
const MIN_HEIGHT: f64 = 400.0;

// Marks every window's webview as the desktop client. Elixir matches the
// `LocalCents/` prefix as a substring (`LocalCentsWeb.Client`) and treats anything
// unstamped as a browser, which is how the same server serves both a native window
// and an ordinary browser tab (see ADR 0023). Note that Tauri *replaces* the
// webview's user agent rather than appending to it, so this is the whole string.
fn desktop_user_agent() -> String {
    format!("LocalCents/{} (desktop)", env!("CARGO_PKG_VERSION"))
}

// The persistent library window: opened at startup and never keyed to a Book.
const LIBRARY_LABEL: &str = "library";
const LIBRARY_PATH: &str = "/library";
// The window title names the window's content, not the app — the app name is
// already in the macOS menu bar (Apple HIG). Document windows are titled by Book
// name; this is the library's equivalent.
const LIBRARY_TITLE: &str = "Library";

/// A command from Elixir, sent as JSON over the `elixirkit` PubSub bridge — the one
/// IPC channel between Elixir and Rust (see `CLAUDE.md`).
///
/// Most commands drive windows. `label` is the window's tag: for `open-window`,
/// re-requesting an already-open label focuses that window instead of duplicating it,
/// which is how "one document window per Book" is enforced; for `close-window` it names
/// the window to close. `path` (the LiveView route to load) and `title` (the native
/// window title) are only carried by `open-window`. `offline` carries the sync link's
/// state for `set-offline-menu`. Every field but `action` defaults, so a command names
/// only the fields it uses.
#[derive(Deserialize)]
struct Command {
    action: String,
    #[serde(default)]
    label: String,
    #[serde(default)]
    path: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    offline: bool,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Shared so the menu-event handler can broadcast to Elixir while `setup` keeps using
    // it to subscribe and to hand Elixir the bridge URL.
    let pubsub =
        Arc::new(elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen"));
    let menu_pubsub = pubsub.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        // Clicking the offline-mode item asks Elixir to flip the link; Elixir owns the
        // state and echoes it back as `set-offline-menu`, which relabels the item.
        .on_menu_event(move |_app, event| {
            if event.id().0.as_str() == OFFLINE_MENU_ID {
                if let Err(e) = menu_pubsub.broadcast("messages", br#"{"action":"toggle-offline"}"#)
                {
                    eprintln!("[rust] failed to broadcast offline toggle: {}", e);
                }
            }
        })
        .setup(move |app| {
            // Keep the platform's standard menus (Quit, Edit, Window) and add Developer;
            // `set_as_app_menu` replaces the whole menu, so it must carry the defaults too.
            let offline_item = MenuItem::with_id(
                app.handle(),
                OFFLINE_MENU_ID,
                ENABLE_OFFLINE_TEXT,
                true,
                None::<&str>,
            )?;
            let developer = SubmenuBuilder::new(app.handle(), "Developer")
                .item(&offline_item)
                .build()?;
            let menu = Menu::default(app.handle())?;
            menu.append(&developer)?;
            menu.set_as_app_menu()?;

            let app_handle = app.handle().clone();
            let offline_item = offline_item.clone();

            pubsub.subscribe("messages", move |msg| {
                if msg == b"ready" {
                    // Launching the app opens the library window (ADR 0006).
                    open_or_focus_window(&app_handle, LIBRARY_LABEL, LIBRARY_PATH, LIBRARY_TITLE);
                } else if let Ok(cmd) = serde_json::from_slice::<Command>(msg) {
                    match cmd.action.as_str() {
                        "open-window" => {
                            open_or_focus_window(&app_handle, &cmd.label, &cmd.path, &cmd.title)
                        }
                        "close-window" => close_window(&app_handle, &cmd.label),
                        "set-title" => set_window_title(&app_handle, &cmd.label, &cmd.title),
                        "set-offline-menu" => set_offline_menu_text(&offline_item, cmd.offline),
                        other => println!("[rust] unknown action: {}", other),
                    }
                } else {
                    println!("[rust] {}", String::from_utf8_lossy(msg));
                }
            });

            let app_handle = app.handle().clone();
            let run_pubsub = pubsub.clone();

            tauri::async_runtime::spawn_blocking(move || {
                let mut command = elixir_command(&app_handle);

                command.env("ELIXIRKIT_PUBSUB", run_pubsub.url());
                let status = command.status().expect("failed to start Elixir");

                app_handle.exit(status.code().unwrap_or(1));
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Opens a native window at `path`, or focuses the existing window tagged `label`.
///
/// Rust tags each window with its `label` (the library, or a Book's `book-<id>`);
/// a request for a label that is already open focuses that window rather than
/// spawning a duplicate. This is what makes the library window persist across
/// opens and enforces one document window per Book (ADR 0006).
fn open_or_focus_window(app_handle: &tauri::AppHandle, label: &str, path: &str, title: &str) {
    if let Some(window) = app_handle.get_webview_window(label) {
        if let Err(e) = window.set_focus() {
            eprintln!("[rust] failed to focus window {}: {}", label, e);
        }
        return;
    }

    let url = tauri::WebviewUrl::External(
        format!("{}{}", BASE_URL, path)
            .parse()
            .expect("failed to build window URL"),
    );

    // Cascade new windows down-and-right so a document window never lands exactly
    // on top of the library (macOS window-cascading convention). The offset is
    // keyed off how many windows are already open, so each successive window steps
    // further from the origin.
    let offset = CASCADE_ORIGIN + app_handle.webview_windows().len() as f64 * CASCADE_STEP;

    let builder = tauri::WebviewWindowBuilder::new(app_handle, label, url)
        .title(title)
        .user_agent(&desktop_user_agent())
        .inner_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        .min_inner_size(MIN_WIDTH, MIN_HEIGHT)
        .position(offset, offset);

    // Let the webview's paper texture paint up into the title bar while the native
    // traffic lights (and, crucially, the green button's native Zoom) stay put — see
    // ADR 0013. `Overlay` is the style that makes AppKit's fullSizeContentView extend
    // the content under a transparent title bar; `Transparent` alone leaves the bar
    // showing the window's background color, not our HTML. `hidden_title` drops the
    // native title text so the HTML title in `Layouts.app` is the only one shown.
    // Both builder methods are macOS-only (the shell is macOS-only for the MVP), so
    // they are cfg-gated to keep other targets compiling.
    #[cfg(target_os = "macos")]
    let builder = builder
        .title_bar_style(tauri::TitleBarStyle::Overlay)
        .hidden_title(true);

    if let Err(e) = builder.build() {
        eprintln!("[rust] failed to open window {}: {}", label, e);
    }
}

/// Closes the native window tagged `label`, if one is open.
///
/// Used when a Book is deleted from the library so its document window goes away
/// immediately (ADR 0006). An unknown label — the Book was never opened — is a
/// no-op, matching the fire-and-forget nature of the PubSub bridge.
fn close_window(app_handle: &tauri::AppHandle, label: &str) {
    if let Some(window) = app_handle.get_webview_window(label) {
        if let Err(e) = window.close() {
            eprintln!("[rust] failed to close window {}: {}", label, e);
        }
    }
}

/// Updates the title bar of the native window tagged `label`, if one is open.
///
/// The native title is set when the window is built and does not follow the
/// webview's document `<title>`, so a Book renamed while its window is open
/// pushes the new title here (ADR 0006). An unknown label is a no-op.
fn set_window_title(app_handle: &tauri::AppHandle, label: &str, title: &str) {
    if let Some(window) = app_handle.get_webview_window(label) {
        if let Err(e) = window.set_title(title) {
            eprintln!("[rust] failed to set title for window {}: {}", label, e);
        }
    }
}

/// Relabels the offline-mode menu item to match the link's state.
///
/// Elixir owns the state and pushes each change here, so the item's title always names
/// the action available next: "Disable Offline Mode" while offline, "Enable Offline
/// Mode" while online (ADR 0025).
fn set_offline_menu_text<R: tauri::Runtime>(item: &MenuItem<R>, offline: bool) {
    let text = if offline {
        DISABLE_OFFLINE_TEXT
    } else {
        ENABLE_OFFLINE_TEXT
    };

    if let Err(e) = item.set_text(text) {
        eprintln!("[rust] failed to relabel the offline menu item: {}", e);
    }
}

fn elixir_command(app_handle: &tauri::AppHandle) -> std::process::Command {
    if cfg!(debug_assertions) {
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command
    } else {
        let rel_dir = app_handle
            .path()
            .resource_dir()
            .expect("Tauri could not resolve the resource directory")
            .join("rel");
        let mut command = elixirkit::release(&rel_dir, "local_cents");
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        // FIXME: We may not want to use port 4000 in a production build since
        // it will collide with other Phoenix apps running on the machine.
        command.env("PORT", "4000");
        command.env(
            "SECRET_KEY_BASE",
            "rZW+joOrOn4gtvRh9HaswYSxFcaIWVQJOGWjk/MATFUyzobypIGdXLn0x5bgZrUx",
        );
        command
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The `LocalCents/` prefix is the cross-language contract: `LocalCentsWeb.Client`
    // matches it as a substring to tell a native window from a browser tab. Changing
    // this string without changing `@desktop_token` there silently turns every native
    // window into a browser.
    #[test]
    fn desktop_user_agent_carries_the_token_elixir_matches() {
        assert!(desktop_user_agent().starts_with("LocalCents/"));
    }

    #[test]
    fn desktop_user_agent_carries_the_crate_version() {
        assert!(desktop_user_agent().contains(env!("CARGO_PKG_VERSION")));
    }
}
