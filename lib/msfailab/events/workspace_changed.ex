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

defmodule Msfailab.Events.WorkspaceChanged do
  @moduledoc """
  Event broadcast when any core entity within a workspace changes.

  This is a lightweight notification event that signals to subscribers that
  something in the workspace's entity structure has changed. This includes:

  - Workspace metadata (name, slug)
  - Container created/updated
  - Track created/updated/archived

  Subscribers should re-fetch the workspace data from the appropriate context
  rather than expecting full state in the event payload.

  ## Design Rationale

  Rather than having separate events for each entity type (ContainerCreated,
  ContainerUpdated, TrackCreated, TrackUpdated), we use a single notification.
  This:

  - Simplifies LiveView handlers (one handler instead of four)
  - Eliminates accumulation logic bugs (no append/update race conditions)
  - Ensures UI always gets consistent, complete state from database
  - Handles missed events gracefully

  ## Usage

  When a LiveView receives this event, it should:
  1. Verify the workspace_id matches the currently displayed workspace
  2. Re-fetch containers with tracks: `Containers.list_containers_with_tracks/1`
  3. Re-assign the containers to the socket

  ## Example

      def handle_info(%WorkspaceChanged{workspace_id: workspace_id}, socket) do
        if socket.assigns.workspace.id == workspace_id do
          containers = Containers.list_containers_with_tracks(socket.assigns.workspace)
          {:noreply, assign(socket, :containers, containers)}
        else
          {:noreply, socket}
        end
      end
  """

  @type t :: %__MODULE__{
          workspace_id: pos_integer(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :timestamp]
  defstruct [:workspace_id, :timestamp]

  @doc """
  Creates a new WorkspaceChanged event.

  ## Parameters

  - `workspace_id` - The workspace that changed
  """
  @spec new(pos_integer()) :: t()
  def new(workspace_id) when is_integer(workspace_id) do
    %__MODULE__{
      workspace_id: workspace_id,
      timestamp: DateTime.utc_now()
    }
  end
end
