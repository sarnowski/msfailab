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

defmodule Msfailab.TracksTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Containers
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.Track
  alias Msfailab.Workspaces

  @workspace_attrs %{slug: "test-workspace", name: "Test Workspace"}
  @container_attrs %{slug: "test-container", name: "Test Container", docker_image: "test:latest"}
  @valid_attrs %{slug: "test-track", name: "Test Track", current_model: "gpt-4"}
  @update_attrs %{name: "Updated Track", current_model: "claude-3"}
  @invalid_attrs %{slug: nil, name: nil}

  defp create_workspace_and_container(_context) do
    {:ok, workspace} = Workspaces.create_workspace(@workspace_attrs)
    {:ok, container} = Containers.create_container(workspace, @container_attrs)
    %{workspace: workspace, container: container}
  end

  describe "list_tracks/1 with workspace struct" do
    setup [:create_workspace_and_container]

    test "returns all active tracks for a workspace", %{
      workspace: workspace,
      container: container
    } do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.list_tracks(workspace) == [track]
    end

    test "excludes archived tracks", %{workspace: workspace, container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      {:ok, _archived} = Tracks.archive_track(track)
      assert Tracks.list_tracks(workspace) == []
    end

    test "only returns tracks for the specified workspace", %{
      workspace: workspace,
      container: container
    } do
      {:ok, workspace2} = Workspaces.create_workspace(%{slug: "workspace", name: "Workspace 2"})
      {:ok, container2} = Containers.create_container(workspace2, @container_attrs)
      {:ok, track1} = Tracks.create_track(container, @valid_attrs)
      {:ok, _track2} = Tracks.create_track(container2, %{@valid_attrs | slug: "track"})
      assert Tracks.list_tracks(workspace) == [track1]
    end
  end

  describe "list_tracks/1 with workspace id" do
    setup [:create_workspace_and_container]

    test "returns all active tracks for a workspace id", %{
      workspace: workspace,
      container: container
    } do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.list_tracks(workspace.id) == [track]
    end
  end

  describe "list_tracks_by_container/1" do
    setup [:create_workspace_and_container]

    test "returns all active tracks for a container", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.list_tracks_by_container(container) == [track]
    end

    test "returns all active tracks for a container id", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.list_tracks_by_container(container.id) == [track]
    end
  end

  describe "list_all_tracks/1" do
    setup [:create_workspace_and_container]

    test "returns all tracks including archived", %{workspace: workspace, container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      {:ok, archived} = Tracks.archive_track(track)
      assert Tracks.list_all_tracks(workspace) == [archived]
    end
  end

  describe "get_track/1" do
    setup [:create_workspace_and_container]

    test "returns track by id", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track(track.id) == track
    end

    test "returns nil for non-existent track" do
      assert Tracks.get_track(999) == nil
    end
  end

  describe "get_track!/1" do
    setup [:create_workspace_and_container]

    test "returns track by id", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track!(track.id) == track
    end

    test "raises for non-existent track" do
      assert_raise Ecto.NoResultsError, fn ->
        Tracks.get_track!(999)
      end
    end
  end

  describe "get_track_by_slug/2 with workspace struct" do
    setup [:create_workspace_and_container]

    test "returns track by slug", %{workspace: workspace, container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track_by_slug(workspace, "test-track") == track
    end

    test "returns nil for non-existent slug", %{workspace: workspace} do
      assert Tracks.get_track_by_slug(workspace, "non-existent") == nil
    end

    test "returns nil for archived track", %{workspace: workspace, container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      {:ok, _archived} = Tracks.archive_track(track)
      assert Tracks.get_track_by_slug(workspace, "test-track") == nil
    end
  end

  describe "get_track_by_slug/2 with workspace id" do
    setup [:create_workspace_and_container]

    test "returns track by slug", %{workspace: workspace, container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track_by_slug(workspace.id, "test-track") == track
    end
  end

  describe "get_track_by_container_and_slug/2" do
    setup [:create_workspace_and_container]

    test "returns track by container and slug", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track_by_container_and_slug(container, "test-track") == track
    end

    test "returns track by container id and slug", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.get_track_by_container_and_slug(container.id, "test-track") == track
    end
  end

  describe "create_track/2 with container struct" do
    setup [:create_workspace_and_container]

    test "creates a track with valid attrs", %{container: container} do
      assert {:ok, %Track{} = track} = Tracks.create_track(container, @valid_attrs)
      assert track.slug == "test-track"
      assert track.name == "Test Track"
      assert track.current_model == "gpt-4"
      assert track.container_id == container.id
      assert track.archived_at == nil
    end

    test "returns error changeset with invalid attrs", %{container: container} do
      assert {:error, %Ecto.Changeset{}} = Tracks.create_track(container, @invalid_attrs)
    end

    test "enforces unique slug within container", %{container: container} do
      {:ok, _track} = Tracks.create_track(container, @valid_attrs)
      assert {:error, changeset} = Tracks.create_track(container, @valid_attrs)
      errors = errors_on(changeset)

      assert "has already been taken" in Map.get(errors, :container_id, []) or
               "has already been taken" in Map.get(errors, :slug, [])
    end

    test "allows same slug in different containers", %{workspace: workspace, container: container} do
      {:ok, container2} =
        Containers.create_container(workspace, %{@container_attrs | slug: "container2"})

      {:ok, _track1} = Tracks.create_track(container, @valid_attrs)
      assert {:ok, %Track{}} = Tracks.create_track(container2, @valid_attrs)
    end
  end

  describe "create_track/2 slug validation" do
    setup [:create_workspace_and_container]

    test "rejects slug starting with number", %{container: container} do
      assert {:error, changeset} = Tracks.create_track(container, %{@valid_attrs | slug: "1test"})
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with consecutive hyphens", %{container: container} do
      assert {:error, changeset} =
               Tracks.create_track(container, %{@valid_attrs | slug: "test--track"})

      assert errors_on(changeset).slug != []
    end

    test "rejects slug exceeding 32 characters", %{container: container} do
      long_slug = "abcdefghijklmnopqrstuvwxyz1234567"

      assert {:error, changeset} =
               Tracks.create_track(container, %{@valid_attrs | slug: long_slug})

      assert errors_on(changeset).slug != []
    end
  end

  describe "create_track/2 name validation" do
    setup [:create_workspace_and_container]

    test "rejects name with leading whitespace", %{container: container} do
      assert {:error, changeset} =
               Tracks.create_track(container, %{@valid_attrs | name: "  Test"})

      assert errors_on(changeset).name != []
    end

    test "rejects name with trailing whitespace", %{container: container} do
      assert {:error, changeset} =
               Tracks.create_track(container, %{@valid_attrs | name: "Test  "})

      assert errors_on(changeset).name != []
    end

    test "rejects name with consecutive spaces", %{container: container} do
      assert {:error, changeset} =
               Tracks.create_track(container, %{@valid_attrs | name: "Test  Name"})

      assert errors_on(changeset).name != []
    end

    test "rejects name with special characters", %{container: container} do
      assert {:error, changeset} = Tracks.create_track(container, %{@valid_attrs | name: "Test!"})
      assert errors_on(changeset).name != []
    end
  end

  describe "create_track/1 with attrs" do
    setup [:create_workspace_and_container]

    test "creates a track with container_id in attrs", %{container: container} do
      attrs = Map.put(@valid_attrs, :container_id, container.id)
      assert {:ok, %Track{}} = Tracks.create_track(attrs)
    end
  end

  describe "update_track/2" do
    setup [:create_workspace_and_container]

    test "updates track with valid attrs", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert {:ok, %Track{} = updated} = Tracks.update_track(track, @update_attrs)
      assert updated.name == "Updated Track"
      assert updated.current_model == "claude-3"
      assert updated.slug == "test-track"
    end

    test "validates name on update", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert {:error, changeset} = Tracks.update_track(track, %{name: "  Invalid  "})
      assert errors_on(changeset).name != []
    end
  end

  describe "archive_track/1" do
    setup [:create_workspace_and_container]

    test "sets archived_at timestamp", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert track.archived_at == nil
      {:ok, archived} = Tracks.archive_track(track)
      assert archived.archived_at != nil
    end
  end

  describe "change_track/2" do
    setup [:create_workspace_and_container]

    test "returns a changeset", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      assert %Ecto.Changeset{} = Tracks.change_track(track)
    end
  end

  describe "update_track_memory/2" do
    alias Msfailab.Tracks.Memory

    setup [:create_workspace_and_container]

    test "updates memory with a Memory struct", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)

      memory = %Memory{
        objective: "Find the router",
        focus: "Scanning network",
        tasks: [],
        working_notes: "Started recon"
      }

      assert {:ok, updated} = Tracks.update_track_memory(track.id, memory)
      assert updated.memory.objective == "Find the router"
      assert updated.memory.focus == "Scanning network"
      assert updated.memory.working_notes == "Started recon"
    end

    test "returns error for non-existent track" do
      memory = Memory.new()
      assert {:error, :not_found} = Tracks.update_track_memory(999, memory)
    end
  end

  describe "slug_exists?/2" do
    setup [:create_workspace_and_container]

    test "returns true for existing slug", %{container: container} do
      {:ok, _track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.slug_exists?(container, "test-track")
    end

    test "returns true for existing slug with container id", %{container: container} do
      {:ok, _track} = Tracks.create_track(container, @valid_attrs)
      assert Tracks.slug_exists?(container.id, "test-track")
    end

    test "returns false for non-existent slug", %{container: container} do
      refute Tracks.slug_exists?(container, "non-existent")
    end

    test "returns false for empty slug", %{container: container} do
      refute Tracks.slug_exists?(container, "")
    end

    test "returns false for nil container_id" do
      refute Tracks.slug_exists?(nil, "test-slug")
    end

    test "returns false for nil slug", %{container: container} do
      refute Tracks.slug_exists?(container.id, nil)
    end
  end

  describe "get_track_with_context/1" do
    setup [:create_workspace_and_container]

    test "returns track with container and workspace preloaded", %{container: container} do
      {:ok, track} = Tracks.create_track(container, @valid_attrs)
      result = Tracks.get_track_with_context(track.id)

      assert result.id == track.id
      assert result.container.id == container.id
      assert result.container.workspace != nil
      assert result.container.workspace.id == container.workspace_id
    end

    test "returns nil for non-existent track" do
      assert Tracks.get_track_with_context(999) == nil
    end
  end

  describe "stop_track_server/1" do
    test "returns :ok when registry is not running" do
      # Without TrackSupervisor running, registry should not be running
      # and stop_track_server should return :ok gracefully
      assert Tracks.stop_track_server(999) == :ok
    end
  end

  describe "get_console_history/1" do
    test "returns {:error, :not_found} when track server is not running" do
      # Without TrackSupervisor running, there are no TrackServers
      assert Tracks.get_console_history(999) == {:error, :not_found}
    end
  end

  describe "get_track_state/1" do
    test "returns {:error, :not_found} when track server is not running" do
      # Without TrackSupervisor running, there are no TrackServers
      assert Tracks.get_track_state(999) == {:error, :not_found}
    end
  end

  # ===========================================================================
  # ConsoleHistoryBlock Tests
  # ===========================================================================

  describe "ConsoleHistoryBlock.new_startup/2" do
    test "creates a startup block with output" do
      block = ConsoleHistoryBlock.new_startup(1, "=[ metasploit v6 ]=\n")

      assert block.track_id == 1
      assert block.type == :startup
      assert block.status == :running
      assert block.output == "=[ metasploit v6 ]=\n"
      assert block.prompt == ""
      assert %DateTime{} = block.started_at
      assert is_nil(block.finished_at)
    end

    test "creates a startup block with default empty output" do
      block = ConsoleHistoryBlock.new_startup(1)

      assert block.track_id == 1
      assert block.output == ""
    end
  end

  describe "ConsoleHistoryBlock.new_command/3" do
    test "creates a command block with command and output" do
      block = ConsoleHistoryBlock.new_command(1, "help", "Core Commands\n")

      assert block.track_id == 1
      assert block.type == :command
      assert block.status == :running
      assert block.command == "help"
      assert block.output == "Core Commands\n"
      assert block.prompt == ""
      assert %DateTime{} = block.started_at
      assert is_nil(block.finished_at)
    end

    test "creates a command block with default empty output" do
      block = ConsoleHistoryBlock.new_command(1, "db_status")

      assert block.track_id == 1
      assert block.command == "db_status"
      assert block.output == ""
    end
  end

  describe "ConsoleHistoryBlock.persist_changeset/1" do
    test "returns error changeset when status is not :finished" do
      block = ConsoleHistoryBlock.new_startup(1, "Banner\n")
      # status is :running by default

      changeset = ConsoleHistoryBlock.persist_changeset(block)

      refute changeset.valid?
      assert {:status, {"must be :finished to persist, got :running", []}} in changeset.errors
    end

    test "returns error when command block has nil command" do
      block = %ConsoleHistoryBlock{
        track_id: 1,
        type: :command,
        status: :finished,
        command: nil,
        output: "Output",
        prompt: "msf6 > ",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      }

      changeset = ConsoleHistoryBlock.persist_changeset(block)

      refute changeset.valid?
      assert {:command, {"is required for command blocks", []}} in changeset.errors
    end

    test "returns error when command block has empty command" do
      block = %ConsoleHistoryBlock{
        track_id: 1,
        type: :command,
        status: :finished,
        command: "",
        output: "Output",
        prompt: "msf6 > ",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      }

      changeset = ConsoleHistoryBlock.persist_changeset(block)

      refute changeset.valid?
      assert {:command, {"is required for command blocks", []}} in changeset.errors
    end

    test "returns error when startup block has a command" do
      block = %ConsoleHistoryBlock{
        track_id: 1,
        type: :startup,
        status: :finished,
        command: "should_not_have_command",
        output: "Banner\n",
        prompt: "msf6 > ",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      }

      changeset = ConsoleHistoryBlock.persist_changeset(block)

      refute changeset.valid?
      assert {:command, {"must be nil for startup blocks", []}} in changeset.errors
    end
  end
end
