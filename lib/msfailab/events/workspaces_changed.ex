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

defmodule Msfailab.Events.WorkspacesChanged do
  @moduledoc """
  Event broadcast when the list of workspaces changes.

  This is a lightweight notification event that signals to subscribers that
  the application's workspace list has changed. This includes:

  - Workspace created
  - Workspace renamed
  - Workspace deleted

  This event is broadcast on the application-wide topic, not a workspace-specific
  topic, since it affects the global workspace list (e.g., home page, workspace
  selector).

  ## Design Rationale

  Rather than including workspace data in the event payload, we use a simple
  notification. This:

  - Keeps event size minimal
  - Ensures UI always gets consistent, complete state
  - Simplifies LiveView logic (no delta accumulation)
  - Handles missed events gracefully

  ## Usage

  When a LiveView receives this event, it should:
  1. Re-fetch the workspace list: `Workspaces.list_workspaces/0`
  2. Re-assign the workspaces to the socket

  ## Example

      def handle_info(%WorkspacesChanged{}, socket) do
        workspaces = Workspaces.list_workspaces()
        {:noreply, assign(socket, :workspaces, workspaces)}
      end
  """

  @type t :: %__MODULE__{
          timestamp: DateTime.t()
        }

  @enforce_keys [:timestamp]
  defstruct [:timestamp]

  @doc """
  Creates a new WorkspacesChanged event.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      timestamp: DateTime.utc_now()
    }
  end
end
