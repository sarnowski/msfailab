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

defmodule Msfailab.Tracks.Reconciler do
  @moduledoc """
  Reconciles database state with running TrackServer GenServers on startup.

  When the application starts, the Reconciler ensures that all active (non-archived)
  tracks have running TrackServer GenServers to maintain session state.

  ## Reconciliation Flow

  ```
  1. Query database for all active tracks (non-archived)
  2. Start TrackServer GenServers for each active track
  3. TrackServers will then subscribe to events and start accumulating state
  ```

  ## Future Enhancements

  In future iterations, the reconciler could:
  - Load persisted command history from database into TrackServer state
  - Load persisted chat history from database
  """

  use GenServer

  require Logger

  alias Msfailab.Tracks.Track
  alias Msfailab.Tracks.TrackServer

  import Ecto.Query

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
    Logger.info("Starting track reconciliation")

    # Get all active (non-archived) tracks with their containers
    active_tracks = list_active_tracks()

    Logger.debug("Found active tracks in database", count: length(active_tracks))

    # Start TrackServer for each active track that doesn't already have one
    started_count =
      active_tracks
      |> Enum.reject(&track_server_exists?/1)
      |> Enum.map(&start_track_server/1)
      |> Enum.count(&match?({:ok, _}, &1))

    Logger.info("Track reconciliation complete", started_count: started_count)
  end

  defp list_active_tracks do
    Track
    |> join(:inner, [t], c in assoc(t, :container))
    |> where([t], is_nil(t.archived_at))
    |> preload(:container)
    |> Msfailab.Repo.all()
  end

  defp track_server_exists?(track) do
    TrackServer.whereis(track.id) != nil
  end

  defp start_track_server(track) do
    opts = [
      track_id: track.id,
      workspace_id: track.container.workspace_id,
      container_id: track.container_id
    ]

    DynamicSupervisor.start_child(
      Msfailab.Tracks.TrackSupervisor,
      {TrackServer, opts}
    )
  end
end
