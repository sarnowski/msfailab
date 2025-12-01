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
# Reason: Pure OTP supervision glue code, no business logic to test
defmodule Msfailab.Containers.Supervisor do
  @moduledoc """
  Supervisor for the container management subsystem.

  Manages the infrastructure for running Docker containers. Console sessions
  for tracks are created on-demand within Container GenServers.

  ## Architecture

  ```
  Containers.Supervisor
  ├── DynamicSupervisor (Msfailab.Containers.ContainerSupervisor)
  │   └── Container GenServers (one per container_record)
  └── Reconciler
      └── Starts Container GenServers on application boot
  ```

  ## Supervision Strategy

  Uses `:one_for_one` strategy because the children are independent:
  - DynamicSupervisor manages independent Container child processes
  - Reconciler only runs on startup
  """

  use Supervisor

  @doc """
  Starts the Containers Supervisor linked to the calling process.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # DynamicSupervisor for Container GenServers
      {DynamicSupervisor, name: Msfailab.Containers.ContainerSupervisor, strategy: :one_for_one},
      # Reconciler runs after supervisor is ready
      Msfailab.Containers.Reconciler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# coveralls-ignore-stop
