use serde::Deserialize;
use tauri::Manager;

// The Phoenix endpoint every window loads from; window commands carry only the
// route path and Rust prepends this host (see ADR 0006).
const BASE_URL: &str = "http://127.0.0.1:4000";

// Window cascade: the first window opens at CASCADE_ORIGIN and each subsequent
// window steps CASCADE_STEP down-and-right, so windows never stack exactly.
const CASCADE_ORIGIN: f64 = 120.0;
const CASCADE_STEP: f64 = 28.0;

// The persistent library window: opened at startup and never keyed to a Book.
const LIBRARY_LABEL: &str = "library";
const LIBRARY_PATH: &str = "/library";
// The window title names the window's content, not the app — the app name is
// already in the macOS menu bar (Apple HIG). Document windows are titled by Book
// name; this is the library's equivalent.
const LIBRARY_TITLE: &str = "Library";

/// A request from Elixir to open (or focus) a native window.
///
/// Sent as JSON over the `elixirkit` PubSub bridge — the one IPC channel between
/// Elixir and Rust (see `CLAUDE.md`). `label` is the window's tag: re-requesting
/// an already-open label focuses that window instead of duplicating it, which is
/// how "one document window per Book" is enforced. `path` is the LiveView route
/// to load and `title` is the native window title.
#[derive(Deserialize)]
struct OpenWindow {
    action: String,
    label: String,
    path: String,
    title: String,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
            let app_handle = app.handle().clone();

            pubsub.subscribe("messages", move |msg| {
                if msg == b"ready" {
                    // Launching the app opens the library window (ADR 0006).
                    open_or_focus_window(&app_handle, LIBRARY_LABEL, LIBRARY_PATH, LIBRARY_TITLE);
                } else if let Ok(cmd) = serde_json::from_slice::<OpenWindow>(msg) {
                    match cmd.action.as_str() {
                        "open-window" => {
                            open_or_focus_window(&app_handle, &cmd.label, &cmd.path, &cmd.title)
                        }
                        other => println!("[rust] unknown window action: {}", other),
                    }
                } else {
                    println!("[rust] {}", String::from_utf8_lossy(msg));
                }
            });

            let app_handle = app.handle().clone();

            tauri::async_runtime::spawn_blocking(move || {
                let mut command = elixir_command(&app_handle);

                command.env("ELIXIRKIT_PUBSUB", pubsub.url());
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

    if let Err(e) = tauri::WebviewWindowBuilder::new(app_handle, label, url)
        .title(title)
        .inner_size(800.0, 600.0)
        .position(offset, offset)
        .build()
    {
        eprintln!("[rust] failed to open window {}: {}", label, e);
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
