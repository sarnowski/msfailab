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

defmodule Msfailab.Tracks.ReconcilerTest do
  use Msfailab.TracksCase, async: false

  alias Msfailab.Containers
  alias Msfailab.Tracks
  alias Msfailab.Tracks.Reconciler
  alias Msfailab.Tracks.TrackServer
  alias Msfailab.Workspaces

  @workspace_attrs %{slug: "test-workspace", name: "Test Workspace"}
  @container_attrs %{slug: "test-container", name: "Test Container", docker_image: "test:latest"}
  @track_attrs %{slug: "test-track", name: "Test Track"}

  defp create_workspace_and_container(_context) do
    {:ok, workspace} = Workspaces.create_workspace(@workspace_attrs)
    {:ok, container} = Containers.create_container(workspace, @container_attrs)
    %{workspace: workspace, container: container}
  end

  describe "reconcile on startup" do
    setup [:create_workspace_and_container]

    test "starts TrackServers for active tracks", %{container: container} do
      # Create a track - but don't have TrackServer running yet
      {:ok, track} = Tracks.create_track(container, @track_attrs)

      # Make sure no TrackServer exists yet
      # (It might have been started by create_track if supervisor was running)
      case TrackServer.whereis(track.id) do
        pid when is_pid(pid) ->
          GenServer.stop(pid, :normal)
          Process.sleep(20)

        nil ->
          :ok
      end

      assert TrackServer.whereis(track.id) == nil

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(30)

      # Verify the TrackServer was started
      assert TrackServer.whereis(track.id) != nil
      assert TrackServer.get_console_status(track.id) == :offline
    end

    test "does not start duplicate TrackServers", %{container: container} do
      # Create a track - TrackServer might be auto-started
      {:ok, track} = Tracks.create_track(container, @track_attrs)

      # Ensure a TrackServer exists (create_track may have started it)
      existing_pid =
        case TrackServer.whereis(track.id) do
          pid when is_pid(pid) ->
            pid

          nil ->
            # Start manually if not auto-started
            opts = [
              track_id: track.id,
              workspace_id: container.workspace_id,
              container_id: container.id
            ]

            {:ok, pid} =
              DynamicSupervisor.start_child(Msfailab.Tracks.TrackSupervisor, {TrackServer, opts})

            pid
        end

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(30)

      # Should still be the same PID (not restarted)
      assert TrackServer.whereis(track.id) == existing_pid
    end

    test "does not start TrackServers for archived tracks", %{container: container} do
      # Create and archive a track
      {:ok, track} = Tracks.create_track(container, @track_attrs)
      {:ok, _archived} = Tracks.archive_track(track)

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(30)

      # No TrackServer should be started for archived track
      assert TrackServer.whereis(track.id) == nil
    end

    test "starts multiple TrackServers for multiple active tracks", %{container: container} do
      # Create multiple tracks
      {:ok, track1} = Tracks.create_track(container, %{@track_attrs | slug: "track-1"})
      {:ok, track2} = Tracks.create_track(container, %{@track_attrs | slug: "track-2"})
      {:ok, track3} = Tracks.create_track(container, %{@track_attrs | slug: "track-3"})

      # Stop any existing TrackServers
      for track <- [track1, track2, track3] do
        case TrackServer.whereis(track.id) do
          pid when is_pid(pid) -> GenServer.stop(pid, :normal)
          nil -> :ok
        end
      end

      Process.sleep(20)

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(50)

      # All TrackServers should be started
      assert TrackServer.whereis(track1.id) != nil
      assert TrackServer.whereis(track2.id) != nil
      assert TrackServer.whereis(track3.id) != nil
    end
  end
end
