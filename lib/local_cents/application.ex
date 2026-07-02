defmodule LocalCents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

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
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    LocalCentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
