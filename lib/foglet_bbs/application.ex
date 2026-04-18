defmodule FogletBbs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FogletBbsWeb.Telemetry,
      FogletBbs.Repo,
      {DNSCluster, query: Application.get_env(:foglet_bbs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FogletBbs.PubSub},
      # Start a worker by calling: FogletBbs.Worker.start_link(arg)
      # {FogletBbs.Worker, arg},
      # Start to serve requests, typically the last entry
      FogletBbsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FogletBbs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FogletBbsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
