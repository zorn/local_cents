defmodule LocalCentsWeb.ClientConn do
  @moduledoc """
  Stamps a test `conn` as one client or the other.

  LocalCents serves both a native desktop window and an ordinary browser tab from the
  same routes, and the two render different affordances (see `LocalCentsWeb.Client` and
  `docs/adr/0023-browser-as-a-second-client.md`). A bare `build_conn/0` sends
  no user agent and would therefore be classified a browser, so `LocalCentsWeb.ConnCase`
  and `LocalCentsWeb.FeatureCase` run `desktop_conn/1` in their setup: the desktop is
  the primary client and the suite's assertions are written for it.

  A test that exercises browser behavior opts in explicitly:

      conn |> browser_conn() |> visit(~p"/library")
  """

  # A stand-in for what `desktop_user_agent()` in `tauri/src/lib.rs` stamps. The
  # version is deliberately not the real one — detection matches the `LocalCents/`
  # token as a substring, and pinning a version here would suggest otherwise.
  @desktop_user_agent "LocalCents/0.0.0-test (desktop)"

  @browser_user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " <>
                        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

  @doc "Stamps `conn` as coming from the native desktop shell."
  @spec desktop_conn(Plug.Conn.t()) :: Plug.Conn.t()
  def desktop_conn(conn), do: Plug.Conn.put_req_header(conn, "user-agent", @desktop_user_agent)

  @doc "Stamps `conn` as coming from an ordinary browser."
  @spec browser_conn(Plug.Conn.t()) :: Plug.Conn.t()
  def browser_conn(conn), do: Plug.Conn.put_req_header(conn, "user-agent", @browser_user_agent)
end
