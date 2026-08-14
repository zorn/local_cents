defmodule LocalCentsWeb.ChannelCase do
  @moduledoc """
  The test case for `Phoenix.Channel` tests: it imports `Phoenix.ChannelTest` and
  points it at `LocalCentsWeb.Endpoint`, so a test can `subscribe_and_join/3` a
  channel and exchange messages with it in-process.

  This is the host side of the sync transport (`LocalCentsWeb.Sync.Channel`); the
  end-to-end exchange over a real WebSocket is covered separately by the
  integration test that dials in with a `LocalCentsWeb.Sync.PeerClient`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint LocalCentsWeb.Endpoint

      import Phoenix.ChannelTest
      import LocalCentsWeb.ChannelCase
    end
  end
end
