defmodule LocalCentsWeb.PageController do
  @moduledoc """
  Sends the root path to the library.

  The native shell never loads `/` — it opens the library window directly at
  `/library` (see `tauri/src/lib.rs` and
  [ADR 0006](0006-multi-window-desktop-shell.html)) — so `/` exists purely so that
  typing the bare host in a browser lands somewhere useful (see
  [ADR 0023](0023-browser-as-a-second-client.html)). Redirecting rather than mounting
  the library at a second path keeps `/library` the one canonical URL that every
  in-app redirect already targets.

  A controller because Phoenix's router has no redirect macro.
  """
  use LocalCentsWeb, :controller

  @spec home(Plug.Conn.t(), params :: map()) :: Plug.Conn.t()
  def home(conn, _params), do: redirect(conn, to: ~p"/library")
end
