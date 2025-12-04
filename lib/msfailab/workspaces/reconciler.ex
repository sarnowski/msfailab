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

defmodule Msfailab.Workspaces.Reconciler do
  @moduledoc """
  Reconciles MSF workspaces with running WorkspaceServer GenServers on startup.

  When the application starts, the Reconciler ensures that all MSF workspaces
  have running WorkspaceServer GenServers to monitor database changes and
  broadcast DatabaseUpdated events.

  ## Reconciliation Flow

  ```
  1. Query MSF database for all workspaces
  2. Start WorkspaceServer GenServers for each workspace
  3. WorkspaceServers will then subscribe to events and start monitoring
  ```
  """

  use GenServer

  require Logger

  alias Msfailab.MsfData.MsfWorkspace
  alias Msfailab.Repo
  alias Msfailab.Workspaces.WorkspaceServer

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
    # Run reconciliation asynchronously to not block startup
    send(self(), :reconcile)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    reconcile()
    {:noreply, state}
  end

  # Private functions

  defp reconcile do
    Logger.info("Starting workspace reconciliation")

    # Get all MSF workspaces
    workspaces = list_msf_workspaces()

    Logger.debug("Found MSF workspaces in database", count: length(workspaces))

    # Start WorkspaceServer for each workspace that doesn't already have one
    started_count =
      workspaces
      |> Enum.reject(&workspace_server_exists?/1)
      |> Enum.map(&start_workspace_server/1)
      |> Enum.count(&match?({:ok, _}, &1))

    Logger.info("Workspace reconciliation complete", started_count: started_count)
  end

  defp list_msf_workspaces do
    Repo.all(MsfWorkspace)
  end

  defp workspace_server_exists?(workspace) do
    WorkspaceServer.whereis(workspace.id) != nil
  end

  defp start_workspace_server(workspace) do
    opts = [
      workspace_id: workspace.id,
      workspace_slug: workspace.name
    ]

    DynamicSupervisor.start_child(
      Msfailab.Workspaces.WorkspaceSupervisor,
      {WorkspaceServer, opts}
    )
  end
end
