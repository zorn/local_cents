defmodule LocalCentsWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Generates a per-request CSP nonce and sets the Content-Security-Policy header.

  The nonce is stored in `conn.assigns.csp_nonce` for use in templates. The
  header this plug sets replaces the static policy the router passes to
  `put_secure_browser_headers`, which exists only for Sobelow's static analysis.
  """

  import Plug.Conn

  @other_directives [
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self' data:",
    "connect-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'"
  ]

  @spec init(opts :: keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), opts :: keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64()

    csp =
      Enum.join(
        ["default-src 'self'", "script-src 'self' 'nonce-#{nonce}'" | @other_directives],
        "; "
      )

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", csp)
  end
end
