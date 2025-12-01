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

defmodule Msfailab.Events.TrackCreated do
  @moduledoc """
  Event broadcast when a new track is created.

  This is the base event in the track event chain. All subsequent track
  events (TrackUpdated) include these same fields plus additional ones,
  enabling self-healing state reconstruction.

  ## Fields

  - `workspace_id` - The workspace containing this track (via container)
  - `container_id` - The container this track belongs to
  - `track_id` - The newly created track's ID
  - `slug` - URL-safe identifier for the track
  - `name` - Human-readable display name
  - `timestamp` - When the track was created

  ## Self-Healing

  If a subscriber misses this event but receives a TrackUpdated,
  they can reconstruct the track's existence from TrackUpdated
  since it includes all fields from TrackCreated.
  """

  alias Msfailab.Tracks.Track

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer(),
          slug: String.t(),
          name: String.t(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :container_id, :track_id, :slug, :name, :timestamp]
  defstruct [:workspace_id, :container_id, :track_id, :slug, :name, :timestamp]

  @doc """
  Creates a new TrackCreated event from a track.

  The track must have its container association loaded with the workspace_id.

  ## Examples

      iex> track = %Track{id: 1, slug: "recon", name: "Initial Recon", container: %{workspace_id: 1}, ...}
      iex> TrackCreated.new(track)
      %TrackCreated{track_id: 1, slug: "recon", name: "Initial Recon", ...}
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
      timestamp: DateTime.utc_now()
    }
  end

  defp get_workspace_id(%Track{container: %{workspace_id: workspace_id}}), do: workspace_id

  defp get_workspace_id(%Track{container: container}) do
    raise ArgumentError,
          "Track must have container with workspace_id loaded, got: #{inspect(container)}"
  end
end
