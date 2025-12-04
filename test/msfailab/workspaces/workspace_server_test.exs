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

defmodule Msfailab.Workspaces.WorkspaceServerTest do
  use Msfailab.DataCase, async: false

  alias Msfailab.Events
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.DatabaseUpdated
  alias Msfailab.MsfData.{Host, MsfWorkspace}
  alias Msfailab.Repo
  alias Msfailab.Workspaces.WorkspaceServer

  setup do
    # Start the registry for this test
    start_supervised!({Registry, keys: :unique, name: Msfailab.Workspaces.Registry})

    # Create MSF workspace
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    workspace =
      %MsfWorkspace{}
      |> Ecto.Changeset.cast(
        %{
          name: "test-workspace-#{System.unique_integer([:positive])}",
          boundary: "10.0.0.0/24",
          description: "Test workspace",
          created_at: now,
          updated_at: now
        },
        [:name, :boundary, :description, :created_at, :updated_at]
      )
      |> Repo.insert!()

    {:ok, workspace: workspace}
  end

  describe "start_link/1" do
    test "starts the server and initializes with zero counts for empty workspace", %{
      workspace: workspace
    } do
      pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace.id, workspace_slug: workspace.name}
        )

      assert Process.alive?(pid)

      counts = WorkspaceServer.get_counts(workspace.id)
      assert counts.total == 0
      assert counts.hosts == 0
    end

    test "loads initial counts from existing data", %{workspace: workspace} do
      # Create some hosts first
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..3 do
        %Host{}
        |> Ecto.Changeset.cast(
          %{
            address: "10.0.0.#{i}",
            state: "alive",
            os_name: "Linux",
            workspace_id: workspace.id,
            created_at: now,
            updated_at: now
          },
          [:address, :state, :os_name, :workspace_id, :created_at, :updated_at]
        )
        |> Repo.insert!()
      end

      _pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace.id, workspace_slug: workspace.name}
        )

      counts = WorkspaceServer.get_counts(workspace.id)
      assert counts.hosts == 3
      assert counts.total == 3
    end
  end

  describe "whereis/1" do
    test "returns pid for running server", %{workspace: workspace} do
      pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace.id, workspace_slug: workspace.name}
        )

      assert WorkspaceServer.whereis(workspace.id) == pid
    end

    test "returns nil for non-existent server" do
      assert WorkspaceServer.whereis(99_999) == nil
    end
  end

  describe "refresh_counts/1" do
    test "manually refreshes counts", %{workspace: workspace} do
      workspace_id = workspace.id

      _pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace_id, workspace_slug: workspace.name}
        )

      # Verify initial count
      counts_before = WorkspaceServer.get_counts(workspace_id)
      assert counts_before.hosts == 0

      # Add a host directly to database
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %Host{}
      |> Ecto.Changeset.cast(
        %{
          address: "10.0.0.1",
          state: "alive",
          workspace_id: workspace_id,
          created_at: now,
          updated_at: now
        },
        [:address, :state, :workspace_id, :created_at, :updated_at]
      )
      |> Repo.insert!()

      # Subscribe to events
      Events.subscribe_to_workspace(workspace_id)

      # Force refresh
      WorkspaceServer.refresh_counts(workspace_id)

      # Wait for the refresh to complete and check for event
      assert_receive %DatabaseUpdated{
                       workspace_id: ^workspace_id,
                       changes: %{hosts: 1},
                       totals: %{hosts: 1}
                     },
                     1000

      # Verify counts updated
      counts_after = WorkspaceServer.get_counts(workspace_id)
      assert counts_after.hosts == 1
    end
  end

  describe "CommandResult triggers refresh" do
    test "finished command triggers count refresh with debounce", %{workspace: workspace} do
      workspace_id = workspace.id

      _pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace_id, workspace_slug: workspace.name}
        )

      # Subscribe to events
      Events.subscribe_to_workspace(workspace_id)

      # Add a host directly to database
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %Host{}
      |> Ecto.Changeset.cast(
        %{
          address: "10.0.0.1",
          state: "alive",
          workspace_id: workspace_id,
          created_at: now,
          updated_at: now
        },
        [:address, :state, :workspace_id, :created_at, :updated_at]
      )
      |> Repo.insert!()

      # Send a CommandResult finished event
      issued = CommandIssued.new(workspace_id, 1, 1, "cmd-123", :metasploit, "db_nmap")
      result = CommandResult.finished(issued, "Scan complete")
      Events.broadcast(result)

      # Wait for debounce (500ms) plus processing time
      assert_receive %DatabaseUpdated{
                       workspace_id: ^workspace_id,
                       changes: %{hosts: 1},
                       totals: %{hosts: 1}
                     },
                     1000

      # Verify counts updated
      counts = WorkspaceServer.get_counts(workspace_id)
      assert counts.hosts == 1
    end

    test "ignores CommandResult from other workspaces", %{workspace: workspace} do
      workspace_id = workspace.id

      _pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace_id, workspace_slug: workspace.name}
        )

      # Subscribe to events
      Events.subscribe_to_workspace(workspace_id)

      # Send a CommandResult from a different workspace
      other_workspace_id = workspace_id + 1000
      issued = CommandIssued.new(other_workspace_id, 1, 1, "cmd-123", :metasploit, "db_nmap")
      result = CommandResult.finished(issued, "Scan complete")
      Events.broadcast(result)

      # Should not receive any DatabaseUpdated event
      refute_receive %DatabaseUpdated{}, 600
    end

    test "ignores running CommandResult status", %{workspace: workspace} do
      workspace_id = workspace.id

      _pid =
        start_supervised!(
          {WorkspaceServer, workspace_id: workspace_id, workspace_slug: workspace.name}
        )

      # Subscribe to events
      Events.subscribe_to_workspace(workspace_id)

      # Send a running CommandResult
      issued = CommandIssued.new(workspace_id, 1, 1, "cmd-123", :metasploit, "db_nmap")
      result = CommandResult.running(issued, "Scanning...")
      Events.broadcast(result)

      # Should not receive any DatabaseUpdated event
      refute_receive %DatabaseUpdated{}, 600
    end
  end
end
