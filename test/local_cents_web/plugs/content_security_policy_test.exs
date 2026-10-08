defmodule LocalCentsWeb.Plugs.ContentSecurityPolicyTest do
  use LocalCentsWeb.ConnCase, async: true

  alias LocalCentsWeb.Plugs.ContentSecurityPolicy

  # opt out of Jump.CredoChecks.AvoidSocketAssignsInTest
  @moduletag :plug_test

  @base_policy "default-src 'self'; script-src 'self'; frame-ancestors 'none'"

  describe "call/2" do
    test "adds the nonce to script-src and keeps the rest of the policy" do
      conn = ContentSecurityPolicy.call(policy_conn(), [])
      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp ==
               "default-src 'self'; script-src 'self' 'nonce-#{conn.assigns.csp_nonce}'; frame-ancestors 'none'"
    end

    test "raises when no policy was set before it" do
      assert_raise ArgumentError, fn -> ContentSecurityPolicy.call(build_conn(), []) end
    end

    test "includes a nonce in the CSP header" do
      conn = ContentSecurityPolicy.call(policy_conn(), [])
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ ~r/nonce-[A-Za-z0-9+\/=]+/
    end

    test "assigns csp_nonce to the conn" do
      conn = ContentSecurityPolicy.call(policy_conn(), [])
      assert byte_size(conn.assigns.csp_nonce) > 0
    end

    test "nonce in CSP header matches the csp_nonce assign" do
      conn = ContentSecurityPolicy.call(policy_conn(), [])
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "nonce-#{conn.assigns.csp_nonce}"
    end

    test "generates a unique nonce per request" do
      conn1 = ContentSecurityPolicy.call(policy_conn(), [])
      conn2 = ContentSecurityPolicy.call(policy_conn(), [])
      refute conn1.assigns.csp_nonce == conn2.assigns.csp_nonce
    end
  end

  describe "browser pipeline integration" do
    @describetag :tmp_dir

    # These render `/library`, which reads the books directory. The assertions are all
    # about headers, so the contents do not matter — but the claim is mandatory: with
    # `raise_on_process_tree_dir_not_set`, an unclaimed render raises rather than falling
    # back to a shared directory.
    setup ~M{tmp_dir} do
      LocalCents.ProcessConfig.put(:books_dir, tmp_dir)
      :ok
    end

    test "serves the full policy with the nonce in script-src", ~M{conn} do
      conn = get(conn, ~p"/library")
      [csp] = get_resp_header(conn, "content-security-policy")

      assert String.replace(csp, ~r/ 'nonce-[A-Za-z0-9+\/=]+'/, "") ==
               "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
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

  defp policy_conn do
    put_resp_header(build_conn(), "content-security-policy", @base_policy)
  end
end
