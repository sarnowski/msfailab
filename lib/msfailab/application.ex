defmodule Msfailab.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Add any custom logger handlers defined in config (e.g., file handler in dev)
    # Truncate app.log first so each session starts fresh (per LOGGING.md)
    if File.exists?("log/app.log"), do: File.write!("log/app.log", "")
    Logger.add_handlers(:msfailab)

    maybe_add_test_logger()
    Msfailab.Trace.reset_files()

    children =
      [
        MsfailabWeb.Telemetry,
        Msfailab.Repo,
        {DNSCluster, query: Application.get_env(:msfailab, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Msfailab.PubSub}
      ] ++
        llm_children() ++
        container_children() ++
        [
          # Start to serve requests, typically the last entry
          MsfailabWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Msfailab.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Returns LLM-related children for the supervision tree.
  # In test mode, these are not started - tests use mocked providers.
  defp llm_children do
    if Application.get_env(:msfailab, :start_llm, true) do
      [Msfailab.LLM.Supervisor]
    else
      []
    end
  end

  # Returns container-related children for the supervision tree.
  # In test mode, these are not started automatically - tests manage their own processes.
  defp container_children do
    if Application.get_env(:msfailab, :start_containers, true) do
      [
        # Registry for container process lookup by container_record_id
        {Registry, keys: :unique, name: Msfailab.Containers.Registry},
        # Registry for track server process lookup by track_id
        {Registry, keys: :unique, name: Msfailab.Tracks.Registry},
        # Container management subsystem
        Msfailab.Containers.Supervisor,
        # Track state management subsystem
        Msfailab.Tracks.Supervisor
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MsfailabWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Conditionally add SilentLogger backend for test environment
  if Mix.env() == :test do
    defp maybe_add_test_logger do
      LoggerBackends.add(SilentLogger)
    end
  else
    defp maybe_add_test_logger do
      :ok
    end
  end
end
