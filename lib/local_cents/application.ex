defmodule LocalCents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LocalCentsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:local_cents, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LocalCents.PubSub},
      # Start a worker by calling: LocalCents.Worker.start_link(arg)
      # {LocalCents.Worker, arg},
      # Start to serve requests, typically the last entry
      LocalCentsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LocalCents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LocalCentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
