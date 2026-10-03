defmodule Octomocto.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OctomoctoWeb.Telemetry,
      Octomocto.Repo,
      {DNSCluster, query: Application.get_env(:octomocto, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Octomocto.PubSub},
      {Registry, keys: :unique, name: Octomocto.Penguin.Registry},
      {DynamicSupervisor, name: Octomocto.Penguin.GameSupervisor},
      # Start a worker by calling: Octomocto.Worker.start_link(arg)
      # {Octomocto.Worker, arg},
      # Start to serve requests, typically the last entry
      OctomoctoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Octomocto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OctomoctoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
