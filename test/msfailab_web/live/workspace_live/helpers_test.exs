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

defmodule MsfailabWeb.WorkspaceLive.HelpersTest do
  use Msfailab.DataCase, async: true

  alias Ecto.Changeset
  alias Msfailab.Containers
  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Tracks
  alias Msfailab.Tracks.Track
  alias Msfailab.Workspaces
  alias MsfailabWeb.WorkspaceLive.Helpers

  # ===========================================================================
  # Page Title Tests
  # ===========================================================================

  describe "page_title/2" do
    test "returns asset library title when track is nil" do
      workspace = %{name: "ACME Pentest"}

      assert Helpers.page_title(workspace, nil) == "ACME Pentest - Asset Library"
    end

    test "returns track title when track is present" do
      workspace = %{name: "ACME Pentest"}
      track = %{name: "Reconnaissance"}

      assert Helpers.page_title(workspace, track) == "Reconnaissance - ACME Pentest"
    end

    test "handles special characters in names" do
      workspace = %{name: "Test & Demo"}
      track = %{name: "Phase 1: Recon"}

      assert Helpers.page_title(workspace, track) == "Phase 1: Recon - Test & Demo"
    end
  end

  # ===========================================================================
  # Console History Rendering Tests
  # ===========================================================================

  alias Msfailab.Tracks.ConsoleHistoryBlock

  describe "blocks_to_segments/1" do
    test "returns empty list for empty blocks" do
      assert Helpers.blocks_to_segments([]) == []
    end

    test "renders first startup block as output only" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "=[ metasploit v6 ]=\n",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [{:output, "=[ metasploit v6 ]=\n"}]
    end

    test "renders command block with previous prompt" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "Banner\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "help",
          output: "Core Commands\n",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [
               {:output, "Banner\n"},
               {:command_line, "msf6 > ", "help"},
               {:output, "Core Commands\n"}
             ]
    end

    test "renders command with empty output (no output segment)" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "Banner\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "clear",
          output: "",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [
               {:output, "Banner\n"},
               {:command_line, "msf6 > ", "clear"}
             ]
    end

    test "renders restart separator for non-first startup block" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "First banner\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "help",
          output: "Help\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :startup,
          output: "Second banner\n",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [
               {:output, "First banner\n"},
               {:command_line, "msf6 > ", "help"},
               {:output, "Help\n"},
               :restart_separator,
               {:output, "Second banner\n"}
             ]
    end

    test "handles multiple commands in sequence" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "Banner\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "db_status",
          output: "[*] Connected\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "hosts",
          output: "Hosts\n=====\n",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [
               {:output, "Banner\n"},
               {:command_line, "msf6 > ", "db_status"},
               {:output, "[*] Connected\n"},
               {:command_line, "msf6 > ", "hosts"},
               {:output, "Hosts\n=====\n"}
             ]
    end

    test "handles different prompts (module context)" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :startup,
          output: "Banner\n",
          prompt: "msf6 > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "use exploit/multi/handler",
          output: "",
          prompt: "msf6 exploit(handler) > ",
          status: :finished
        },
        %ConsoleHistoryBlock{
          type: :command,
          command: "show options",
          output: "Options\n",
          prompt: "msf6 exploit(handler) > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      assert result == [
               {:output, "Banner\n"},
               {:command_line, "msf6 > ", "use exploit/multi/handler"},
               {:command_line, "msf6 exploit(handler) > ", "show options"},
               {:output, "Options\n"}
             ]
    end

    test "handles command block at index 0 (edge case - uses empty prompt)" do
      blocks = [
        %ConsoleHistoryBlock{
          type: :command,
          command: "help",
          output: "Help text\n",
          prompt: "msf6 > ",
          status: :finished
        }
      ]

      result = Helpers.blocks_to_segments(blocks)

      # Edge case: command at index 0 has no previous block, so empty prompt
      assert result == [
               {:command_line, "", "help"},
               {:output, "Help text\n"}
             ]
    end
  end

  # ===========================================================================
  # Track Form Helper Tests
  # ===========================================================================

  describe "validate_track_slug_uniqueness/2" do
    setup do
      {:ok, workspace} =
        Workspaces.create_workspace(%{name: "Test Workspace", slug: "test-ws-track"})

      {:ok, container} =
        Containers.create_container(workspace, %{
          name: "Test Container",
          slug: "test-container",
          docker_image: "test:latest"
        })

      %{workspace: workspace, container: container}
    end

    test "returns unchanged changeset when container is nil" do
      changeset = Changeset.change(%Track{}, %{slug: "any-slug"})

      result = Helpers.validate_track_slug_uniqueness(changeset, nil)

      assert result.errors == []
    end

    test "returns unchanged changeset when slug does not exist", %{container: container} do
      changeset = Changeset.change(%Track{}, %{slug: "unique-slug-12345"})

      result = Helpers.validate_track_slug_uniqueness(changeset, container)

      assert result.errors == []
    end

    test "adds error when slug already exists", %{container: container} do
      # Create a track first
      {:ok, _track} =
        Tracks.create_track(container, %{name: "Existing Track", slug: "existing-track"})

      changeset = Changeset.change(%Track{}, %{slug: "existing-track"})

      result = Helpers.validate_track_slug_uniqueness(changeset, container)

      assert {:slug, {"is already taken", []}} in result.errors
    end

    test "returns unchanged changeset when slug is nil", %{container: container} do
      changeset = Changeset.change(%Track{}, %{slug: nil})

      result = Helpers.validate_track_slug_uniqueness(changeset, container)

      assert result.errors == []
    end
  end

  describe "track_slug_helper/3" do
    test "returns full URL with slug when valid" do
      field = %{value: "my-track", errors: []}

      result = Helpers.track_slug_helper(field, "test-workspace", "https://example.com")

      assert result == "https://example.com/test-workspace/my-track"
    end

    test "returns placeholder when slug is empty" do
      field = %{value: "", errors: []}

      result = Helpers.track_slug_helper(field, "test-workspace", "https://example.com")

      assert result == "https://example.com/test-workspace/your-slug"
    end

    test "returns placeholder when slug is nil" do
      field = %{value: nil, errors: []}

      result = Helpers.track_slug_helper(field, "test-workspace", "https://example.com")

      assert result == "https://example.com/test-workspace/your-slug"
    end

    test "returns placeholder when field has errors" do
      field = %{value: "valid-slug", errors: [slug: {"invalid", []}]}

      result = Helpers.track_slug_helper(field, "test-workspace", "https://example.com")

      assert result == "https://example.com/test-workspace/your-slug"
    end
  end

  # ===========================================================================
  # Container Form Helper Tests
  # ===========================================================================

  describe "validate_container_slug_uniqueness/2" do
    setup do
      {:ok, workspace} =
        Workspaces.create_workspace(%{name: "Test Workspace", slug: "test-ws-container"})

      %{workspace: workspace}
    end

    test "returns unchanged changeset when slug does not exist", %{workspace: workspace} do
      changeset = Changeset.change(%ContainerRecord{}, %{slug: "unique-slug-12345"})

      result = Helpers.validate_container_slug_uniqueness(changeset, workspace)

      assert result.errors == []
    end

    test "adds error when slug already exists", %{workspace: workspace} do
      # Create a container first
      {:ok, _container} =
        Containers.create_container(workspace, %{
          name: "Existing",
          slug: "existing-container",
          docker_image: "test:latest"
        })

      changeset = Changeset.change(%ContainerRecord{}, %{slug: "existing-container"})

      result = Helpers.validate_container_slug_uniqueness(changeset, workspace)

      assert {:slug, {"is already taken", []}} in result.errors
    end

    test "returns unchanged changeset when slug is nil", %{workspace: workspace} do
      changeset = Changeset.change(%ContainerRecord{}, %{slug: nil})

      result = Helpers.validate_container_slug_uniqueness(changeset, workspace)

      assert result.errors == []
    end
  end

  describe "container_slug_helper/2" do
    test "returns Docker container name when slug is valid" do
      field = %{value: "my-container", errors: []}

      result = Helpers.container_slug_helper(field, "test-workspace")

      assert result == "Docker container: msfailab-test-workspace-my-container"
    end

    test "returns placeholder when slug is empty" do
      field = %{value: "", errors: []}

      result = Helpers.container_slug_helper(field, "test-workspace")

      assert result == "Docker container: msfailab-test-workspace-your-slug"
    end

    test "returns placeholder when slug is nil" do
      field = %{value: nil, errors: []}

      result = Helpers.container_slug_helper(field, "test-workspace")

      assert result == "Docker container: msfailab-test-workspace-your-slug"
    end

    test "returns placeholder when field has errors" do
      field = %{value: "valid-slug", errors: [slug: {"invalid", []}]}

      result = Helpers.container_slug_helper(field, "test-workspace")

      assert result == "Docker container: msfailab-test-workspace-your-slug"
    end
  end

  # ===========================================================================
  # Container Lookup Tests
  # ===========================================================================

  describe "find_container/2" do
    test "finds container by id" do
      containers = [
        %{id: 1, name: "First"},
        %{id: 2, name: "Second"},
        %{id: 3, name: "Third"}
      ]

      assert Helpers.find_container(containers, 2) == %{id: 2, name: "Second"}
    end

    test "returns nil when container not found" do
      containers = [%{id: 1, name: "Only"}]

      assert Helpers.find_container(containers, 999) == nil
    end

    test "returns nil for empty list" do
      assert Helpers.find_container([], 1) == nil
    end
  end
end
