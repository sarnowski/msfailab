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

defmodule Msfailab.Tools.MemoryExecutorTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tools.MemoryExecutor
  alias Msfailab.Tracks
  alias Msfailab.Tracks.Memory
  alias Msfailab.Tracks.Memory.Task

  # Helper to create a track with optional initial memory
  defp create_track_with_memory(memory_attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    {:ok, workspace} =
      Msfailab.Workspaces.create_workspace(%{slug: "test-#{unique}", name: "Test #{unique}"})

    {:ok, container} =
      Msfailab.Containers.create_container(workspace, %{
        slug: "container-#{unique}",
        name: "Container #{unique}",
        docker_image: "test:latest"
      })

    {:ok, track} =
      Tracks.create_track(container, %{
        name: "Track #{unique}",
        slug: "track-#{unique}"
      })

    # Update memory if attrs provided
    if map_size(memory_attrs) > 0 do
      memory = struct(Memory, memory_attrs)
      {:ok, track} = Tracks.update_track_memory(track.id, memory)
      track
    else
      track
    end
  end

  describe "handles_tool?/1" do
    test "returns true for memory tools" do
      assert MemoryExecutor.handles_tool?("read_memory") == true
      assert MemoryExecutor.handles_tool?("update_memory") == true
      assert MemoryExecutor.handles_tool?("add_task") == true
      assert MemoryExecutor.handles_tool?("update_task") == true
      assert MemoryExecutor.handles_tool?("remove_task") == true
    end

    test "returns false for non-memory tools" do
      assert MemoryExecutor.handles_tool?("execute_msfconsole_command") == false
      assert MemoryExecutor.handles_tool?("list_hosts") == false
      assert MemoryExecutor.handles_tool?("unknown") == false
    end
  end

  describe "execute/3 with read_memory" do
    test "returns current memory state from DB" do
      track =
        create_track_with_memory(%{
          objective: "Test objective",
          focus: "Test focus",
          tasks: [%Task{id: "1", content: "Task 1", status: :pending}],
          working_notes: "Notes"
        })

      {:ok, result} = MemoryExecutor.execute("read_memory", %{}, %{track_id: track.id})

      assert result["objective"] == "Test objective"
      assert result["focus"] == "Test focus"
      assert result["working_notes"] == "Notes"
      assert length(result["tasks"]) == 1
    end

    test "returns empty memory for new track" do
      track = create_track_with_memory()

      {:ok, result} = MemoryExecutor.execute("read_memory", %{}, %{track_id: track.id})

      assert result["objective"] == nil
      assert result["focus"] == nil
      assert result["tasks"] == []
    end

    test "returns error for invalid track_id" do
      {:error, {:track_not_found, message}} =
        MemoryExecutor.execute("read_memory", %{}, %{track_id: 999_999})

      assert message =~ "Track not found"
    end
  end

  describe "execute/3 with update_memory" do
    test "updates objective field and persists to DB" do
      track = create_track_with_memory()

      {:ok, result} =
        MemoryExecutor.execute("update_memory", %{"objective" => "New goal"}, %{
          track_id: track.id
        })

      assert result["objective"] == "New goal"

      # Verify persisted to DB
      updated_track = Tracks.get_track(track.id)
      assert updated_track.memory.objective == "New goal"
    end

    test "updates focus field" do
      track = create_track_with_memory()

      {:ok, result} =
        MemoryExecutor.execute("update_memory", %{"focus" => "Current work"}, %{
          track_id: track.id
        })

      assert result["focus"] == "Current work"
    end

    test "updates multiple fields" do
      track = create_track_with_memory()

      {:ok, result} =
        MemoryExecutor.execute(
          "update_memory",
          %{"objective" => "Goal", "focus" => "Focus"},
          %{track_id: track.id}
        )

      assert result["objective"] == "Goal"
      assert result["focus"] == "Focus"
    end

    test "preserves existing values when not updated" do
      track = create_track_with_memory(%{objective: "Existing", focus: "Also existing"})

      {:ok, result} =
        MemoryExecutor.execute("update_memory", %{"focus" => "New focus"}, %{track_id: track.id})

      assert result["objective"] == "Existing"
      assert result["focus"] == "New focus"
    end
  end

  describe "execute/3 with add_task" do
    test "adds a new task and persists to DB" do
      track = create_track_with_memory()

      {:ok, result} =
        MemoryExecutor.execute("add_task", %{"content" => "New task"}, %{track_id: track.id})

      assert length(result["tasks"]) == 1
      task = hd(result["tasks"])
      assert task["content"] == "New task"
      assert task["status"] == "pending"

      # Verify persisted
      updated_track = Tracks.get_track(track.id)
      assert length(updated_track.memory.tasks) == 1
    end

    test "returns error when content is missing" do
      track = create_track_with_memory()

      {:error, {:missing_parameter, message}} =
        MemoryExecutor.execute("add_task", %{}, %{track_id: track.id})

      assert message =~ "content"
    end
  end

  describe "execute/3 with update_task" do
    test "updates task status to completed" do
      track =
        create_track_with_memory(%{
          tasks: [%Task{id: "task-1", content: "Task", status: :pending}]
        })

      {:ok, result} =
        MemoryExecutor.execute(
          "update_task",
          %{"id" => "task-1", "status" => "completed"},
          %{track_id: track.id}
        )

      assert hd(result["tasks"])["status"] == "completed"
    end

    test "updates task status to in_progress" do
      track =
        create_track_with_memory(%{
          tasks: [%Task{id: "task-1", content: "Task", status: :pending}]
        })

      {:ok, result} =
        MemoryExecutor.execute(
          "update_task",
          %{"id" => "task-1", "status" => "in_progress"},
          %{track_id: track.id}
        )

      assert hd(result["tasks"])["status"] == "in_progress"
    end

    test "updates task status to pending" do
      track =
        create_track_with_memory(%{
          tasks: [%Task{id: "task-1", content: "Task", status: :completed}]
        })

      {:ok, result} =
        MemoryExecutor.execute(
          "update_task",
          %{"id" => "task-1", "status" => "pending"},
          %{track_id: track.id}
        )

      assert hd(result["tasks"])["status"] == "pending"
    end

    test "updates task content" do
      track =
        create_track_with_memory(%{
          tasks: [%Task{id: "task-1", content: "Original", status: :pending}]
        })

      {:ok, result} =
        MemoryExecutor.execute(
          "update_task",
          %{"id" => "task-1", "content" => "Updated"},
          %{track_id: track.id}
        )

      assert hd(result["tasks"])["content"] == "Updated"
    end

    test "returns error for missing id" do
      track = create_track_with_memory()

      {:error, {:missing_parameter, message}} =
        MemoryExecutor.execute("update_task", %{"status" => "completed"}, %{track_id: track.id})

      assert message =~ "id"
    end

    test "returns error for unknown task id" do
      track = create_track_with_memory()

      {:error, {:task_not_found, message}} =
        MemoryExecutor.execute("update_task", %{"id" => "unknown"}, %{track_id: track.id})

      assert message =~ "not found"
    end
  end

  describe "execute/3 with remove_task" do
    test "removes task by id" do
      track =
        create_track_with_memory(%{
          tasks: [%Task{id: "task-1", content: "Task", status: :pending}]
        })

      {:ok, result} =
        MemoryExecutor.execute("remove_task", %{"id" => "task-1"}, %{track_id: track.id})

      assert result["tasks"] == []
    end

    test "returns error when id is missing" do
      track = create_track_with_memory()

      {:error, {:missing_parameter, message}} =
        MemoryExecutor.execute("remove_task", %{}, %{track_id: track.id})

      assert message =~ "id"
    end

    test "handles non-existent task id gracefully" do
      track = create_track_with_memory()

      {:ok, result} =
        MemoryExecutor.execute("remove_task", %{"id" => "unknown"}, %{track_id: track.id})

      assert result["tasks"] == []
    end
  end
end
