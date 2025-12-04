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
defmodule Msfailab.Workspaces.Supervisor do
  @moduledoc """
  Supervisor for the workspace monitoring subsystem.

  Manages WorkspaceServer GenServers that monitor MSF database changes for each
  workspace. Each workspace has one WorkspaceServer that caches asset counts and
  broadcasts DatabaseUpdated events when counts change.

  ## Architecture

  ```
  Workspaces.Supervisor
  ├── DynamicSupervisor (Msfailab.Workspaces.WorkspaceSupervisor)
  │   └── WorkspaceServer GenServers (one per workspace)
  └── Reconciler
      └── Starts WorkspaceServer GenServers on application boot
  ```

  ## Supervision Strategy

  Uses `:one_for_one` strategy because the children are independent:
  - DynamicSupervisor manages independent WorkspaceServer child processes
  - Reconciler only runs on startup
  """

  use Supervisor

  @doc """
  Starts the Workspaces Supervisor linked to the calling process.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # DynamicSupervisor for WorkspaceServer GenServers
      {DynamicSupervisor, name: Msfailab.Workspaces.WorkspaceSupervisor, strategy: :one_for_one},
      # Reconciler runs after supervisor is ready
      Msfailab.Workspaces.Reconciler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# coveralls-ignore-stop
