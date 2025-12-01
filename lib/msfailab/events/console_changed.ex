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

defmodule Msfailab.Events.ConsoleChanged do
  @moduledoc """
  Event broadcast when a track's console state changes.

  This is a lightweight notification event that signals to subscribers that
  the track's console state has changed. Subscribers should query the
  TrackServer for the current state rather than expecting full state in
  the event payload.

  ## Design Rationale

  Rather than including console data in the event payload, we use a simple
  notification. This:

  - Keeps event size minimal
  - Ensures UI always gets consistent, complete state
  - Simplifies LiveView logic (no delta accumulation)
  - Handles missed events gracefully

  ## Usage

  When a LiveView receives this event, it should:
  1. Check if the track_id matches the currently displayed track
  2. Query `Tracks.get_console_state/1` for the full state
  3. Re-render the terminal pane with the new state

  ## Example

      def handle_info(%ConsoleChanged{track_id: track_id}, socket) do
        if socket.assigns.current_track?.id == track_id do
          {status, prompt, segments} = Tracks.get_console_state(track_id)
          socket =
            socket
            |> assign(:console_status, status)
            |> assign(:current_prompt, prompt)
            |> assign(:console_segments, segments)
          {:noreply, socket}
        else
          {:noreply, socket}
        end
      end
  """

  @type t :: %__MODULE__{
          workspace_id: pos_integer(),
          track_id: pos_integer(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :track_id, :timestamp]
  defstruct [:workspace_id, :track_id, :timestamp]

  @doc """
  Creates a new ConsoleChanged event.

  ## Parameters

  - `workspace_id` - The workspace containing the track
  - `track_id` - The track whose console state changed
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(workspace_id, track_id) when is_integer(workspace_id) and is_integer(track_id) do
    %__MODULE__{
      workspace_id: workspace_id,
      track_id: track_id,
      timestamp: DateTime.utc_now()
    }
  end
end
