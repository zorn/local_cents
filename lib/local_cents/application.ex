defmodule LocalCents.Application do
  @moduledoc """
  The OTP application entry point — it builds and starts the supervision tree.

  LocalCents runs as a single Phoenix instance that a [Tauri](https://tauri.app)
  native shell spawns and drives (see the `README` and the project's Tauri notes
  for the bigger picture). This module is where that process tree is assembled.

  ## Supervised children

  Started under a `:one_for_one` supervisor, in order:

    * `LocalCentsWeb.Telemetry` — metrics and instrumentation.
    * `DNSCluster` — inert here. It ships in the `phx.new` scaffold for
      multi-instance node clustering, but LocalCents is a single-instance desktop
      app, so `DNS_CLUSTER_QUERY` is never set and it starts as a no-op.
    * `Phoenix.PubSub` — in-app process messaging.
    * `ElixirKit.PubSub` — the TCP bridge to the Rust/Tauri side. This is the one
      IPC channel between Elixir and native code.
    * `LocalCentsWeb.Endpoint` — the Phoenix HTTP endpoint.
    * A one-off `Task` that sends the `"ready"` handshake (see below).

  ## Tauri vs. standalone startup

  Startup branches on the `ELIXIRKIT_PUBSUB` environment variable:

    * **Launched by Tauri** — the native shell sets `ELIXIRKIT_PUBSUB` to the
      address it is listening on. `ElixirKit.PubSub` connects to it, and once the
      tree is up the startup `Task` broadcasts `"ready"` on the `"messages"`
      channel so Tauri knows it can open the WebView window.
    * **Standalone (`mix phx.server`, tests)** — the variable is unset, so
      `ElixirKit.PubSub` starts with `connect: :ignore` (a no-op) and no `"ready"`
      message is sent. This lets us develop and test the Phoenix side in complete
      isolation from the native shell.

  ## Boundary

  This module is promoted to a top-level `Boundary` so it can depend on the other
  top-level boundaries it wires into the supervision tree — the web layer
  (`LocalCentsWeb`) and the tracking context (`LocalCents.Tracking`) — without
  those layers having to depend on each other. See
  [Module Boundaries](module-boundaries.html).
  """

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications

  # As the OTP entry point this module names every child it wires into the
  # supervision tree, so its dependency breadth is inherent to that role rather than a
  # smell to refactor away (the same reasoning `LocalCents.Tracking.BookServer` uses to
  # opt out). Adding the sync `PeerClient` child pushed it one past the project-wide cap,
  # so it opts out here rather than inflating the cap for every module.
  # credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies

  # Promoted to a top-level boundary so it can depend on both the core and the
  # web layer to wire up the supervision tree, without creating a dependency
  # cycle between `LocalCents` and `LocalCentsWeb`.
  use Boundary, top_level?: true, deps: [LocalCents.Tracking, LocalCentsWeb]

  use Application

  @impl Application
  def start(_type, _args) do
    pubsub = System.get_env("ELIXIRKIT_PUBSUB")

    children = [
      LocalCentsWeb.Telemetry,

      # DNSCluster ships in the `phx.new` scaffold to enable one-env-var node
      # clustering for multi-instance web deploys (e.g. Fly.io, Kubernetes). We
      # don't use it: LocalCents is a single-instance Tauri desktop app with no
      # clustering story. `DNS_CLUSTER_QUERY` is never set, so `query:` falls
      # back to `:ignore` and this child starts as a no-op. We keep it in place
      # for `phx.new` parity and in case a networked mode ever wants it.
      {DNSCluster, query: Application.get_env(:local_cents, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LocalCents.PubSub},

      # The tracking context's per-Book runtime (registry + dynamic supervisor for
      # `LocalCents.Tracking.BookServer` processes; see ADR 0007). Started after
      # `Phoenix.PubSub` because a BookServer broadcasts changes over it.
      LocalCents.Tracking.Supervisor,

      # See <https://hexdocs.pm/elixirkit/tauri.html#phoenix-tauri>
      {ElixirKit.PubSub, connect: pubsub || :ignore, on_exit: fn -> System.stop() end},

      # Start a worker by calling: LocalCents.Worker.start_link(arg)
      # {LocalCents.Worker, arg},
      # Start to serve requests, typically the last entry
      LocalCentsWeb.Endpoint,

      # If `ELIXIRKIT_PUBSUB` env var is set, which we will from our Tauri app,
      # we connect to PubSub and send a ready message. Otherwise, we start
      # `ElixirKit.PubSub` with connect: `:ignore` which does nothing -- this
      # way we can develop and test the Phoenix side in isolation.
      {Task,
       fn ->
         if pubsub do
           ElixirKit.PubSub.broadcast("messages", "ready")
         end
       end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LocalCents.Supervisor]
    Supervisor.start_link(children ++ sync_peer_children(), opts)
  end

  # The two-peer sync link, started only when this instance is configured to dial a
  # peer (ADR 0025). `LOCAL_CENTS_SYNC_URL` is the WebSocket URL of the peer's
  # `LocalCentsWeb.PeerSocket` and `LOCAL_CENTS_SYNC_BOOK_ID` is the Book both sides
  # reconcile; without them this instance only *hosts* the sync Channel and starts no
  # client. The client tolerates the Book not being open yet, so ordering after the
  # rest of the tree is enough — it idles until the Book is opened and edited.
  @spec sync_peer_children() :: [Supervisor.child_spec() | {module(), term()}]
  defp sync_peer_children do
    url = System.get_env("LOCAL_CENTS_SYNC_URL")
    book_id = System.get_env("LOCAL_CENTS_SYNC_BOOK_ID")

    if url && book_id do
      [{LocalCentsWeb.Sync.PeerClient, uri: url, book_id: book_id}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    LocalCentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
