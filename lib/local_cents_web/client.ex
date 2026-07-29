defmodule LocalCentsWeb.Client do
  @moduledoc """
  Which client a page is rendering into — the native desktop window or a browser tab.

  LocalCents ships as a Tauri desktop app, but the same Phoenix server is also driven
  from an ordinary browser during development, and every screen is expected to work
  there (see [ADR 0023](0023-browser-as-a-second-client.html)). The two differ in what
  the shell can do for them: on the desktop, opening a Book means asking Rust for a
  native window (`LocalCentsWeb.DesktopShell`), and the title strip is chrome painted
  into a transparent native title bar. In a browser neither is true, so those
  affordances become links.

  Views tell the two apart through the `@client` assign, put there by `on_mount/4` —
  attached once in `LocalCentsWeb.live_view/0`, so every view has it.

  The signal is the webview's user agent, which Rust stamps with `desktop_token/0`
  when it builds a window. That token is a cross-language contract, so — like the
  window-command wire format in `DesktopShell` — it is defined in exactly one place
  on the Elixir side. It is matched as a *substring* so the version it carries can
  drift without breaking detection. A request that is not stamped is a browser: the
  desktop is the case that has to announce itself, and an unstamped browser getting
  browser behavior is the outcome we want by default.

  Detection happens once per request in `LocalCentsWeb.Plugs.Client`, which puts the
  result in the session. Reading it from the session rather than from connect params
  is what makes it correct on the *disconnected* first render as well as the connected
  mount — a native window never paints browser chrome and then corrects itself.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket

  @typedoc "The client a page is rendering into."
  @type t() :: :desktop | :browser

  # Stamped into the webview's user agent by `open_or_focus_window` in
  # `tauri/src/lib.rs`, which every native window is built through.
  @desktop_token "LocalCents/"

  # Where `LocalCentsWeb.Plugs.Client` leaves the detected client for `on_mount/4`.
  @session_key "client"

  @doc "The user-agent substring that marks a request as coming from the native shell."
  @spec desktop_token() :: String.t()
  def desktop_token, do: @desktop_token

  @doc "The session key the plug and the mount hook agree on."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @doc """
  Classifies a request's `user_agent`.

  Anything without the desktop token — including a request that sent no user agent
  at all — is a browser.
  """
  @spec from_user_agent(String.t() | nil) :: t()
  def from_user_agent(user_agent) when is_binary(user_agent) do
    if String.contains?(user_agent, @desktop_token), do: :desktop, else: :browser
  end

  def from_user_agent(nil), do: :browser

  @doc """
  Assigns `:client` from the session.

  Attached in `LocalCentsWeb.live_view/0` rather than per view: unlike
  `LocalCentsWeb.BookWindow` — which encodes a contract only the document-window views
  rely on — every view renders into a client, so this is universal and cannot be
  usefully forgotten.
  """
  @spec on_mount(:default, params :: map(), session :: map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :client, from_session(session))}
  end

  @doc """
  Reads the client the plug left in `session`.

  A session the plug never touched — a stale one from before this existed — must not
  crash a mount, so anything unrecognized is the browser, matching an unstamped user
  agent.
  """
  @spec from_session(session :: map()) :: t()
  def from_session(%{@session_key => "desktop"}), do: :desktop
  def from_session(_session), do: :browser
end
