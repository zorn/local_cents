defmodule LocalCentsWeb.Plugs.ContentSecurityPolicyTest do
  use LocalCentsWeb.ConnCase, async: true

  alias LocalCentsWeb.Plugs.ContentSecurityPolicy

  # opt out of Jump.CredoChecks.AvoidSocketAssignsInTest
  @moduletag :plug_test

  describe "call/2" do
    test "sets the content-security-policy response header" do
      conn = ContentSecurityPolicy.call(build_conn(), [])
      assert get_resp_header(conn, "content-security-policy") != []
    end

    test "includes a nonce in the CSP header" do
      conn = ContentSecurityPolicy.call(build_conn(), [])
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ ~r/nonce-[A-Za-z0-9+\/=]+/
    end

    test "assigns csp_nonce to the conn" do
      conn = ContentSecurityPolicy.call(build_conn(), [])
      assert byte_size(conn.assigns.csp_nonce) > 0
    end

    test "nonce in CSP header matches the csp_nonce assign" do
      conn = ContentSecurityPolicy.call(build_conn(), [])
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "nonce-#{conn.assigns.csp_nonce}"
    end

    test "generates a unique nonce per request" do
      conn1 = ContentSecurityPolicy.call(build_conn(), [])
      conn2 = ContentSecurityPolicy.call(build_conn(), [])
      refute conn1.assigns.csp_nonce == conn2.assigns.csp_nonce
    end
  end

  describe "fallback_csp/0" do
    test "omits the per-request nonce" do
      refute ContentSecurityPolicy.fallback_csp() =~ "nonce-"
    end

    test "includes expected directives" do
      csp = ContentSecurityPolicy.fallback_csp()
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
      assert csp =~ "frame-ancestors 'none'"
      assert csp =~ "form-action 'self'"
    end
  end

  describe "browser pipeline integration" do
    @describetag :tmp_dir

    # These render `/library`, which reads the books directory. The assertions are all
    # about headers, so the contents do not matter — but setting a directory is good hygiene.
    setup ~M{tmp_dir} do
      LocalCents.ProcessConfig.put(:books_dir, tmp_dir)
      :ok
    end

    test "includes CSP header on browser requests", ~M{conn} do
      conn = get(conn, ~p"/")
      assert get_resp_header(conn, "content-security-policy") != []
    end

    # `/` only redirects to the library, so this asserts against a route that actually
    # renders the root layout's inline theme script.
    test "nonce in CSP header matches the nonce attribute on the inline script tag", ~M{conn} do
      conn = get(conn, ~p"/library")
      [csp] = get_resp_header(conn, "content-security-policy")
      [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9+\/=]+)'/, csp)
      assert conn.resp_body =~ ~s(nonce="#{nonce}")
    end
  end
end
