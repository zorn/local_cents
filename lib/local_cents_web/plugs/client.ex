defmodule LocalCentsWeb.Plugs.Client do
  @moduledoc """
  Detects the request's client and leaves it in the session for LiveView to read.

  Classifies the user agent with `LocalCentsWeb.Client.from_user_agent/1` and stores
  the result under `LocalCentsWeb.Client.session_key/0`. The session is the handoff
  because a LiveView's `mount/3` receives it on *both* the disconnected first render
  and the connected mount, so a native window never paints browser chrome for a beat
  before correcting itself.

  Runs on every browser request rather than once per session, so a client is never
  inherited from a stale cookie.

  Must be plugged after `:fetch_session`.
  """

  import Plug.Conn

  alias LocalCentsWeb.Client

  @spec init(opts :: keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), opts :: keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    client =
      conn
      |> get_req_header("user-agent")
      |> List.first()
      |> Client.from_user_agent()

    put_session(conn, Client.session_key(), Atom.to_string(client))
  end
end
