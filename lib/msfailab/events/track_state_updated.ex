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

defmodule Msfailab.Events.TrackStateUpdated do
  @moduledoc """
  Event broadcast when a track's runtime state changes.

  This is a lightweight notification event that signals to subscribers that
  the track's session state has changed. Subscribers should query the
  TrackServer for the current state rather than expecting full state in
  the event payload.

  This is a **State Event** (see Events module documentation), meaning it
  represents changes to runtime session state within an entity, not changes
  to the entity itself.

  ## Usage

  When a LiveView receives this event, it should:
  1. Check if the track_id matches the currently displayed track
  2. Query `Tracks.get_command_history/1` for the updated state
  3. Re-render the terminal pane with the new state

  ## Example

      def handle_info(%TrackStateUpdated{track_id: track_id}, socket) do
        if track_id == socket.assigns.track.id do
          commands = Tracks.get_command_history(track_id)
          {:noreply, assign(socket, :commands, commands)}
        else
          {:noreply, socket}
        end
      end
  """

  @type t :: %__MODULE__{
          workspace_id: integer(),
          track_id: integer(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :track_id, :timestamp]
  defstruct [:workspace_id, :track_id, :timestamp]

  @doc """
  Creates a new TrackStateUpdated event.

  ## Parameters

  - `workspace_id` - The workspace containing the track
  - `track_id` - The track whose state changed
  """
  @spec new(integer(), integer()) :: t()
  def new(workspace_id, track_id) when is_integer(workspace_id) and is_integer(track_id) do
    %__MODULE__{
      workspace_id: workspace_id,
      track_id: track_id,
      timestamp: DateTime.utc_now()
    }
  end
end
