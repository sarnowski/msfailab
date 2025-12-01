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

# coveralls-ignore-start
# Reason: Behaviour module - only defines callbacks, no executable code
defmodule Msfailab.Containers.DockerAdapter do
  @moduledoc """
  Behaviour defining the contract for Docker container operations.

  This abstraction enables testing container management logic without
  actual Docker containers by using Mox to create mock implementations.

  ## Container Identification

  Containers are identified by their Docker container ID (a hex string).
  They are also named using a predictable format: `msfailab-{workspace_slug}-{track_slug}`.

  ## Labels

  All managed containers have the following labels:
  - `msfailab.managed=true` - identifies containers managed by this application
  - `msfailab.track_id={id}` - the database track ID
  - `msfailab.workspace_slug={slug}` - the workspace slug
  - `msfailab.track_slug={slug}` - the track slug
  """

  @typedoc "Docker container ID (hex string)"
  @type container_id :: String.t()

  @typedoc "Container name in format msfailab-{workspace_slug}-{track_slug}"
  @type container_name :: String.t()

  @typedoc "Container status"
  @type container_status :: :running | :exited | :created | :paused | :dead

  @typedoc "Information about a running container"
  @type container_info :: %{
          id: container_id(),
          name: container_name(),
          status: container_status(),
          labels: %{String.t() => String.t()}
        }

  @doc """
  Starts a new container with the given name and labels.

  Returns `{:ok, container_id}` on success or `{:error, reason}` on failure.
  """
  @callback start_container(name :: container_name(), labels :: map()) ::
              {:ok, container_id()} | {:error, term()}

  @doc """
  Stops a running container.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback stop_container(container_id()) ::
              :ok | {:error, term()}

  @doc """
  Checks if a container is currently running.

  Returns `true` if the container exists and is running, `false` otherwise.
  """
  @callback container_running?(container_id()) ::
              boolean()

  @doc """
  Lists all containers managed by this application.

  Filters containers by the `msfailab.managed=true` label.
  Returns `{:ok, containers}` on success or `{:error, reason}` on failure.
  """
  @callback list_managed_containers() ::
              {:ok, [container_info()]} | {:error, term()}

  @doc """
  Executes a command inside a running container.

  Returns `{:ok, output, exit_code}` when the process completes (regardless of exit code),
  or `{:error, reason}` on infrastructure failure (couldn't spawn process, container not found, etc.).

  The exit code is passed through without interpretation - a non-zero exit code is not an error
  from the adapter's perspective, it's just informational.
  """
  @callback exec(container_id(), command :: String.t()) ::
              {:ok, output :: String.t(), exit_code :: integer()} | {:error, term()}

  @typedoc "RPC endpoint for connecting to MSF console"
  @type rpc_endpoint :: %{
          host: String.t(),
          port: pos_integer()
        }

  @doc """
  Gets the RPC endpoint for a running container.

  In development (port mapping mode), returns localhost with the mapped port.
  In production (network mode), returns the container name with the standard port.

  Returns `{:ok, endpoint}` with host and port, or `{:error, reason}` on failure.
  """
  @callback get_rpc_endpoint(container_id()) ::
              {:ok, rpc_endpoint()} | {:error, term()}
end

# coveralls-ignore-stop
