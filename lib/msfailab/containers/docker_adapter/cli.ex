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
# Reason: External system boundary module, mocked in tests via DockerAdapterMock
defmodule Msfailab.Containers.DockerAdapter.Cli do
  @moduledoc """
  Docker adapter implementation using the Docker CLI.

  This module implements the `DockerAdapter` behaviour by shelling out
  to the `docker` command-line tool.

  ## Current Status

  This implementation is currently **stubbed** for development purposes.
  All operations log their intent but do not actually execute Docker commands.
  This allows the container management infrastructure to be tested without
  requiring a running Docker daemon.

  ## Future Implementation

  When ready, each function will use `System.cmd/3` to execute Docker commands:
  - `docker run` for starting containers
  - `docker stop` for stopping containers
  - `docker ps` for listing containers
  - `docker exec` for executing commands
  """

  @behaviour Msfailab.Containers.DockerAdapter

  require Logger

  @impl true
  @spec start_container(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def start_container(name, labels) do
    Logger.info("DockerAdapter.Cli: Would start container",
      name: name,
      labels: inspect(labels)
    )

    # Stub: Generate a fake container ID
    container_id = generate_fake_container_id()
    {:ok, container_id}
  end

  @impl true
  @spec stop_container(String.t()) :: :ok | {:error, term()}
  def stop_container(container_id) do
    Logger.info("DockerAdapter.Cli: Would stop container", container_id: container_id)
    :ok
  end

  @impl true
  @spec container_running?(String.t()) :: boolean()
  def container_running?(container_id) do
    Logger.debug("DockerAdapter.Cli: Would check if container is running",
      container_id: container_id
    )

    # Stub: Always return true for fake container IDs
    true
  end

  @impl true
  @spec list_managed_containers() :: {:ok, [map()]} | {:error, term()}
  def list_managed_containers do
    Logger.debug("DockerAdapter.Cli: Would list managed containers")
    # Stub: Return empty list (no containers exist yet)
    {:ok, []}
  end

  @impl true
  @spec exec(String.t(), String.t()) :: {:ok, String.t(), integer()} | {:error, term()}
  def exec(container_id, command) do
    Logger.info("DockerAdapter.Cli: Would exec in container",
      container_id: container_id,
      command: command
    )

    # Stub: Return empty output with exit code 0
    {:ok, "", 0}
  end

  @impl true
  @spec get_rpc_endpoint(String.t()) :: {:ok, map()} | {:error, term()}
  def get_rpc_endpoint(container_id) do
    Logger.debug("DockerAdapter.Cli: Would get RPC endpoint for container",
      container_id: container_id
    )

    # Stub: Return a fake RPC endpoint
    {:ok, %{host: "localhost", port: 55_553}}
  end

  # Private functions

  defp generate_fake_container_id do
    # Generate a fake 12-character hex ID like Docker does
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end
end

# coveralls-ignore-stop
