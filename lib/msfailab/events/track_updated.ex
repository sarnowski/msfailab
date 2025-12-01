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

defmodule Msfailab.Events.TrackUpdated do
  @moduledoc """
  Event broadcast when a track is updated or archived.

  This event extends TrackCreated with archive status information.
  It is emitted for database updates (name changes) and when tracks
  are archived.

  ## Fields (from TrackCreated)

  - `workspace_id` - The workspace containing this track (via container)
  - `container_id` - The container this track belongs to
  - `track_id` - The track's ID
  - `slug` - URL-safe identifier for the track
  - `name` - Human-readable display name

  ## Additional Fields

  - `archived_at` - When the track was archived (nil if active)
  - `timestamp` - When the update occurred

  ## Self-Healing

  If a subscriber misses TrackCreated but receives this event,
  they can reconstruct the track's full state since all entity
  fields are included.
  """

  alias Msfailab.Tracks.Track

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer(),
          slug: String.t(),
          name: String.t(),
          archived_at: DateTime.t() | nil,
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :container_id, :track_id, :slug, :name, :timestamp]
  defstruct [:workspace_id, :container_id, :track_id, :slug, :name, :archived_at, :timestamp]

  @doc """
  Creates a new TrackUpdated event from a track.

  The track must have its container association loaded with the workspace_id.

  ## Examples

      iex> track = %Track{id: 1, slug: "recon", name: "Initial Recon", archived_at: nil, ...}
      iex> TrackUpdated.new(track)
      %TrackUpdated{track_id: 1, archived_at: nil, ...}

      iex> archived_track = %Track{id: 1, archived_at: ~U[2024-01-01 00:00:00Z], ...}
      iex> TrackUpdated.new(archived_track)
      %TrackUpdated{track_id: 1, archived_at: ~U[2024-01-01 00:00:00Z], ...}
  """
  @spec new(Track.t()) :: t()
  def new(%Track{} = track) do
    workspace_id = get_workspace_id(track)

    %__MODULE__{
      workspace_id: workspace_id,
      container_id: track.container_id,
      track_id: track.id,
      slug: track.slug,
      name: track.name,
      archived_at: track.archived_at,
      timestamp: DateTime.utc_now()
    }
  end

  defp get_workspace_id(%Track{container: %{workspace_id: workspace_id}}), do: workspace_id

  defp get_workspace_id(%Track{container: container}) do
    raise ArgumentError,
          "Track must have container with workspace_id loaded, got: #{inspect(container)}"
  end
end
