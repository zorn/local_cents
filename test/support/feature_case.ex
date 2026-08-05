# TODO: I question the need for these timeout customizations and may consider trashing this in favor of ConnCase.
defmodule LocalCentsWeb.FeatureCase do
  @moduledoc """
  This module defines the test case to be used by feature tests that drive the
  UI the way a user would, via `PhoenixTest`.

  Tests read as high-level user flows (`visit/2`, `click_button/2`,
  `fill_in/3`, `assert_has/3`) and work against both dead and live views
  transparently. Reach for this case when you want to exercise a page end to
  end; use `LocalCentsWeb.ConnCase` for lower-level connection assertions.
  """

  use ExUnit.CaseTemplate

  # PhoenixTest defaults `assert_has`/`refute_has` to `timeout: 0` — a single, eager
  # check. That is too eager for our pages that load content via `assign_async` (e.g.
  # the Report), which resolves a beat after the initial render. Rather than sprinkle
  # `timeout:` on every such assertion, `FeatureCase` defaults them all to this small
  # retry window; an assertion still returns the instant it is satisfied, so tests that
  # do not wait pay nothing. Pass an explicit `timeout:` to override per call.
  @default_assertion_timeout 500

  using do
    quote do
      # The default endpoint for testing
      @endpoint LocalCentsWeb.Endpoint

      use LocalCentsWeb, :verified_routes

      # Shadow PhoenixTest's `assert_has`/`refute_has` with the default-timeout wrappers
      # below; everything else comes straight from PhoenixTest.
      import PhoenixTest, except: [assert_has: 2, assert_has: 3, refute_has: 2, refute_has: 3]
      import LocalCentsWeb.ClientConn
      import LocalCentsWeb.FeatureCase

      # The `~M` sigil for map shorthand, e.g. `~M{conn}` for `%{conn: conn}`.
      import TinyMaps
    end
  end

  @typedoc "A PhoenixTest session — the value threaded through `visit/2`, `click_*`, etc."
  @type session() :: term()

  @doc "Like `PhoenixTest.assert_has/3`, but defaulting `timeout:` (see the module note)."
  @spec assert_has(session(), String.t(), keyword()) :: session()
  def assert_has(session, selector, opts \\ []) do
    PhoenixTest.assert_has(session, selector, with_default_timeout(opts))
  end

  @doc "Like `PhoenixTest.refute_has/3`, but defaulting `timeout:` (see the module note)."
  @spec refute_has(session(), String.t(), keyword()) :: session()
  def refute_has(session, selector, opts \\ []) do
    PhoenixTest.refute_has(session, selector, with_default_timeout(opts))
  end

  defp with_default_timeout(opts), do: Keyword.put_new(opts, :timeout, @default_assertion_timeout)

  # The conn is stamped as the desktop client: feature tests drive the app the way a
  # user does, and the primary client is the native window. A browser-mode test opts in
  # with `browser_conn/1` — see `LocalCentsWeb.ClientConn`.
  setup _tags do
    conn =
      Phoenix.ConnTest.build_conn()
      |> LocalCentsWeb.ClientConn.desktop_conn()
      |> PhoenixTest.put_endpoint(LocalCentsWeb.Endpoint)

    {:ok, conn: conn}
  end
end
