defmodule LocalCentsWeb.ClientTest do
  use ExUnit.Case, async: true

  alias LocalCentsWeb.Client

  describe "from_user_agent/1" do
    test "a user agent carrying the desktop token is the desktop client" do
      assert Client.from_user_agent("LocalCents/0.1.0 (desktop)") == :desktop
    end

    test "the token is matched as a substring, so the version can drift" do
      assert Client.from_user_agent("LocalCents/99.4.7-rc1 (desktop)") == :desktop
    end

    test "an ordinary browser user agent is the browser client" do
      safari =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " <>
          "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

      assert Client.from_user_agent(safari) == :browser
    end

    test "a missing user agent is the browser client" do
      assert Client.from_user_agent(nil) == :browser
    end
  end

  # What `on_mount/4` assigns. The hook itself is exercised by every feature test, which
  # asserts the rendering each client actually produces.
  describe "from_session/1" do
    test "reads the desktop client the plug left behind" do
      assert Client.from_session(%{Client.session_key() => "desktop"}) == :desktop
    end

    test "reads the browser client the plug left behind" do
      assert Client.from_session(%{Client.session_key() => "browser"}) == :browser
    end

    # A session predating this (or one the plug never touched) must not crash a mount.
    test "falls back to the browser client when the session carries nothing" do
      assert Client.from_session(%{}) == :browser
    end

    test "falls back to the browser client on an unrecognized value" do
      assert Client.from_session(%{Client.session_key() => "kiosk"}) == :browser
    end
  end
end
