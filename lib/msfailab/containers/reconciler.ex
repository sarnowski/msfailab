# Metasploit Framework AI Lab - Collaborative security research with AI agents
# Copyright (C) 2025 Tobias Sarnowski
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

defmodule Msfailab.Containers.Reconciler do
  @moduledoc """
  Reconciles database state with running Docker containers and GenServers on startup.

  When the application starts, the Reconciler ensures that:
  1. All containers with active tracks have running Container GenServers
  2. Orphaned Docker containers are stopped

  Console sessions for tracks are created on-demand when commands are sent,
  so no track-specific reconciliation is needed.

  ## Reconciliation Flow

  ```
  1. Query database for active containers (containers with non-archived tracks)
  2. Query Docker for containers with msfailab.managed=true label
  3. Start Container GenServers for each active container:
     - If matching Docker container exists, adopt it
     - Otherwise, a new Docker container will be started
  4. Stop orphaned Docker containers:
     - Docker containers whose container_id doesn't match any active container
  ```

  ## Docker Labels

  Managed Docker containers are labeled with:
  - `msfailab.managed=true` - Indicates this container is managed by msfailab
  - `msfailab.container_id=<id>` - The database ID of the container record
  - `msfailab.workspace_slug=<slug>` - The workspace slug
  - `msfailab.container_slug=<slug>` - The container slug
  """

  use GenServer

  require Logger

  alias Msfailab.Containers
  alias Msfailab.Containers.Container
  alias Msfailab.Containers.DockerAdapter

  @doc """
  Starts the Reconciler process linked to the calling process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Start Container GenServers SYNCHRONOUSLY during init.
    # This ensures they are registered in the Registry before Tracks.Supervisor starts,
    # allowing TrackServers to call register_console without race conditions.
    start_container_genservers_sync()

    # Docker operations (adopting existing containers) run async to not block startup
    send(self(), :reconcile_docker)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile_docker, state) do
    reconcile_docker()
    {:noreply, state}
  end

  # Private functions

  defp start_container_genservers_sync do
    Logger.info("Starting container reconciliation")

    # Get database truth: all active containers (with at least one non-archived track)
    active_containers = Containers.list_active_containers()

    Logger.debug("Found active containers in database", count: length(active_containers))

    # Start Container GenServers synchronously (they start in :offline state)
    # This ensures they exist before Tracks.Reconciler runs
    started_count =
      active_containers
      |> Enum.reject(&container_genserver_exists?/1)
      |> Enum.map(&start_container_genserver_offline/1)
      |> Enum.count(&match?({:ok, _}, &1))

    Logger.info("Container GenServers started", started_count: started_count)
  end

  defp reconcile_docker do
    # Now reconcile with Docker to adopt existing containers
    active_containers = Containers.list_active_containers()
    active_container_ids = MapSet.new(active_containers, & &1.id)

    case docker_adapter().list_managed_containers() do
      {:ok, running_docker_containers} ->
        reconcile_with_docker(active_container_ids, running_docker_containers)

      {:error, reason} ->
        Logger.error("Failed to list Docker containers during reconciliation",
          reason: inspect(reason)
        )
    end

    Logger.info("Container reconciliation complete")
  end

  defp reconcile_with_docker(active_container_ids, running_docker_containers) do
    # Build a map of container_record_id -> docker_container_info
    docker_by_container_id =
      running_docker_containers
      |> Enum.map(fn docker_container ->
        container_id_str = Map.get(docker_container.labels, "msfailab.container_id")

        case container_id_str && Integer.parse(container_id_str) do
          {container_id, ""} -> {container_id, docker_container}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    running_container_ids = MapSet.new(Map.keys(docker_by_container_id))

    Logger.debug("Found managed Docker containers running",
      count: map_size(docker_by_container_id)
    )

    # Stop orphaned Docker containers (running but container_id doesn't match any active container)
    orphaned_container_ids = MapSet.difference(running_container_ids, active_container_ids)
    stop_orphaned_docker_containers(orphaned_container_ids, docker_by_container_id)

    # Notify running Container GenServers about existing Docker containers they can adopt
    adopt_docker_containers(active_container_ids, docker_by_container_id)
  end

  defp stop_orphaned_docker_containers(orphaned_container_ids, docker_by_container_id) do
    for container_id <- orphaned_container_ids do
      docker_container = Map.fetch!(docker_by_container_id, container_id)

      Logger.info("Stopping orphaned Docker container",
        docker_container_id: docker_container.id,
        container_record_id: container_id
      )

      docker_adapter().stop_container(docker_container.id)
    end

    orphan_count = MapSet.size(orphaned_container_ids)

    if orphan_count > 0 do
      Logger.info("Stopped orphaned Docker containers", count: orphan_count)
    end
  end

  defp adopt_docker_containers(active_container_ids, docker_by_container_id) do
    # For each active container, either adopt existing Docker container or start new
    for container_id <- active_container_ids do
      case Map.get(docker_by_container_id, container_id) do
        nil ->
          # No existing Docker container, tell GenServer to start a new one
          Container.start_new(container_id)

        docker_container ->
          # Notify the Container GenServer to adopt this Docker container
          Container.adopt_docker_container(container_id, docker_container.id)
      end
    end
  end

  defp container_genserver_exists?(container) do
    Container.whereis(container.id) != nil
  end

  defp start_container_genserver_offline(container) do
    # Start Container GenServer without Docker container ID.
    # It will start in :offline state and either adopt an existing Docker
    # container (via adopt_docker_container) or start a new one.
    opts = [
      container_record_id: container.id,
      workspace_id: container.workspace_id,
      workspace_slug: container.workspace.slug,
      container_slug: container.slug,
      container_name: container.name,
      docker_image: container.docker_image
    ]

    DynamicSupervisor.start_child(
      Msfailab.Containers.ContainerSupervisor,
      {Container, opts}
    )
  end

  defp docker_adapter do
    Application.get_env(:msfailab, :docker_adapter, DockerAdapter.Cli)
  end
end
