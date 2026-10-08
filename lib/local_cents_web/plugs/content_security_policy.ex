defmodule LocalCentsWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Adds a per-request nonce to the Content-Security-Policy header.

  The policy itself is the literal the router passes to `put_secure_browser_headers`,
  which keeps it in one place that Sobelow's static analysis can read. This plug runs
  after it and allows the nonce in `script-src`, so the root layout's inline script can
  run without loosening the policy for any other script. The nonce is stored in
  `conn.assigns.csp_nonce` for use in templates.
  """

  import Plug.Conn

  @script_src "script-src 'self'"

  @spec init(opts :: keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), opts :: keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64()

    csp =
      conn
      |> get_resp_header("content-security-policy")
      |> add_nonce(nonce)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", csp)
  end

  # Raising beats passing the policy through: without the nonce the inline script is
  # blocked, and that failure only shows up as a console error in the browser.
  defp add_nonce([policy], nonce) do
    if String.contains?(policy, @script_src) do
      String.replace(policy, @script_src, "#{@script_src} 'nonce-#{nonce}'", global: false)
    else
      raise ArgumentError, "expected the content-security-policy to contain #{@script_src}"
    end
  end

  defp add_nonce(_headers, _nonce) do
    raise ArgumentError,
          "expected one content-security-policy header, set by put_secure_browser_headers"
  end
end
