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

  using do
    quote do
      # The default endpoint for testing
      @endpoint LocalCentsWeb.Endpoint

      use LocalCentsWeb, :verified_routes

      import LocalCentsWeb.FeatureCase
      import PhoenixTest

      # The `~M` sigil for map shorthand, e.g. `~M{conn}` for `%{conn: conn}`.
      import TinyMaps
    end
  end

  setup _tags do
    conn = PhoenixTest.put_endpoint(Phoenix.ConnTest.build_conn(), LocalCentsWeb.Endpoint)
    {:ok, conn: conn}
  end
end
