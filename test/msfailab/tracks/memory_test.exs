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

defmodule Msfailab.Tracks.MemoryTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.Memory
  alias Msfailab.Tracks.Memory.Task

  # ===========================================================================
  # Task Embedded Schema Tests
  # ===========================================================================

  describe "Task embedded schema" do
    test "creates a task with required fields" do
      task = %Task{
        id: "uuid-123",
        content: "Port scan 10.0.0.0/24",
        status: :pending
      }

      assert task.id == "uuid-123"
      assert task.content == "Port scan 10.0.0.0/24"
      assert task.status == :pending
    end

    test "supports all valid task statuses" do
      for status <- [:pending, :in_progress, :completed] do
        task = %Task{id: "id", content: "task", status: status}
        assert task.status == status
      end
    end
  end

  # ===========================================================================
  # Memory Embedded Schema Tests
  # ===========================================================================

  describe "Memory embedded schema" do
    test "creates memory with default values" do
      memory = %Memory{}

      assert memory.objective == nil
      assert memory.focus == nil
      assert memory.tasks == []
      assert memory.working_notes == nil
    end

    test "creates memory with all fields populated" do
      task = %Task{id: "task-1", content: "Scan network", status: :completed}

      memory = %Memory{
        objective: "Gain domain admin access",
        focus: "Enumerating SMB shares",
        tasks: [task],
        working_notes: "DC likely at 10.0.0.5"
      }

      assert memory.objective == "Gain domain admin access"
      assert memory.focus == "Enumerating SMB shares"
      assert length(memory.tasks) == 1
      assert memory.working_notes == "DC likely at 10.0.0.5"
    end
  end

  # ===========================================================================
  # Memory.new/0 Tests
  # ===========================================================================

  describe "Memory.new/0" do
    test "creates a new empty memory" do
      memory = Memory.new()

      assert memory.objective == nil
      assert memory.focus == nil
      assert memory.tasks == []
      assert memory.working_notes == nil
    end
  end

  # ===========================================================================
  # Memory.update/2 Tests
  # ===========================================================================

  describe "Memory.update/2" do
    test "updates objective field only" do
      memory = Memory.new()
      updated = Memory.update(memory, %{objective: "New objective"})

      assert updated.objective == "New objective"
      assert updated.focus == nil
      assert updated.tasks == []
      assert updated.working_notes == nil
    end

    test "updates focus field only" do
      memory = Memory.new()
      updated = Memory.update(memory, %{focus: "Current focus"})

      assert updated.objective == nil
      assert updated.focus == "Current focus"
    end

    test "updates working_notes field only" do
      memory = Memory.new()
      updated = Memory.update(memory, %{working_notes: "Some notes"})

      assert updated.working_notes == "Some notes"
    end

    test "replaces entire tasks array when provided" do
      task1 = %Task{id: "1", content: "Task 1", status: :pending}
      task2 = %Task{id: "2", content: "Task 2", status: :completed}
      memory = %Memory{tasks: [task1]}

      updated = Memory.update(memory, %{tasks: [task2]})

      assert length(updated.tasks) == 1
      assert hd(updated.tasks).id == "2"
    end

    test "updates multiple fields at once" do
      memory = Memory.new()

      updated =
        Memory.update(memory, %{
          objective: "Objective",
          focus: "Focus",
          working_notes: "Notes"
        })

      assert updated.objective == "Objective"
      assert updated.focus == "Focus"
      assert updated.working_notes == "Notes"
    end

    test "preserves existing values when not updated" do
      memory = %Memory{
        objective: "Existing objective",
        focus: "Existing focus",
        tasks: [],
        working_notes: "Existing notes"
      }

      updated = Memory.update(memory, %{focus: "New focus"})

      assert updated.objective == "Existing objective"
      assert updated.focus == "New focus"
      assert updated.working_notes == "Existing notes"
    end

    test "ignores unknown keys in changes map" do
      memory = Memory.new()
      updated = Memory.update(memory, %{unknown_field: "value", objective: "Goal"})

      # Unknown field is ignored, known field is updated
      assert updated.objective == "Goal"
      refute Map.has_key?(updated, :unknown_field)
    end
  end

  # ===========================================================================
  # Memory.add_task/2 Tests
  # ===========================================================================

  describe "Memory.add_task/2" do
    test "appends a new task with auto-generated UUID" do
      memory = Memory.new()
      updated = Memory.add_task(memory, "New task")

      assert length(updated.tasks) == 1
      task = hd(updated.tasks)
      assert task.content == "New task"
      assert task.status == :pending
      # UUID should be a valid format
      assert String.length(task.id) == 36
      assert String.contains?(task.id, "-")
    end

    test "appends tasks to existing list" do
      existing_task = %Task{id: "existing", content: "Existing", status: :completed}
      memory = %Memory{tasks: [existing_task]}

      updated = Memory.add_task(memory, "New task")

      assert length(updated.tasks) == 2
      # New task is appended at the end
      assert Enum.at(updated.tasks, 0).id == "existing"
      assert Enum.at(updated.tasks, 1).content == "New task"
    end
  end

  # ===========================================================================
  # Memory.update_task/3 Tests
  # ===========================================================================

  describe "Memory.update_task/3" do
    test "updates task content by id" do
      task = %Task{id: "task-1", content: "Original", status: :pending}
      memory = %Memory{tasks: [task]}

      {:ok, updated} = Memory.update_task(memory, "task-1", %{content: "Updated"})

      assert hd(updated.tasks).content == "Updated"
      assert hd(updated.tasks).status == :pending
    end

    test "updates task status by id" do
      task = %Task{id: "task-1", content: "Task", status: :pending}
      memory = %Memory{tasks: [task]}

      {:ok, updated} = Memory.update_task(memory, "task-1", %{status: :in_progress})

      assert hd(updated.tasks).status == :in_progress
      assert hd(updated.tasks).content == "Task"
    end

    test "updates both content and status" do
      task = %Task{id: "task-1", content: "Task", status: :pending}
      memory = %Memory{tasks: [task]}

      {:ok, updated} =
        Memory.update_task(memory, "task-1", %{content: "New content", status: :completed})

      assert hd(updated.tasks).content == "New content"
      assert hd(updated.tasks).status == :completed
    end

    test "returns error for unknown task id" do
      task = %Task{id: "task-1", content: "Task", status: :pending}
      memory = %Memory{tasks: [task]}

      assert {:error, :task_not_found} =
               Memory.update_task(memory, "unknown-id", %{status: :completed})
    end

    test "updates correct task in list of multiple tasks" do
      task1 = %Task{id: "task-1", content: "Task 1", status: :pending}
      task2 = %Task{id: "task-2", content: "Task 2", status: :pending}
      task3 = %Task{id: "task-3", content: "Task 3", status: :pending}
      memory = %Memory{tasks: [task1, task2, task3]}

      {:ok, updated} = Memory.update_task(memory, "task-2", %{status: :completed})

      assert Enum.at(updated.tasks, 0).status == :pending
      assert Enum.at(updated.tasks, 1).status == :completed
      assert Enum.at(updated.tasks, 2).status == :pending
    end
  end

  # ===========================================================================
  # Memory.remove_task/2 Tests
  # ===========================================================================

  describe "Memory.remove_task/2" do
    test "removes task by id" do
      task = %Task{id: "task-1", content: "Task", status: :pending}
      memory = %Memory{tasks: [task]}

      updated = Memory.remove_task(memory, "task-1")

      assert updated.tasks == []
    end

    test "removes correct task from list of multiple" do
      task1 = %Task{id: "task-1", content: "Task 1", status: :pending}
      task2 = %Task{id: "task-2", content: "Task 2", status: :pending}
      task3 = %Task{id: "task-3", content: "Task 3", status: :pending}
      memory = %Memory{tasks: [task1, task2, task3]}

      updated = Memory.remove_task(memory, "task-2")

      assert length(updated.tasks) == 2
      assert Enum.at(updated.tasks, 0).id == "task-1"
      assert Enum.at(updated.tasks, 1).id == "task-3"
    end

    test "returns unchanged memory when task id not found" do
      task = %Task{id: "task-1", content: "Task", status: :pending}
      memory = %Memory{tasks: [task]}

      updated = Memory.remove_task(memory, "unknown-id")

      assert length(updated.tasks) == 1
      assert hd(updated.tasks).id == "task-1"
    end
  end

  # ===========================================================================
  # Memory.serialize/1 Tests
  # ===========================================================================

  describe "Memory.serialize/1" do
    test "serializes empty memory" do
      memory = Memory.new()
      result = Memory.serialize(memory)

      assert result == "## Track Memory\n\n*No memory set*"
    end

    test "serializes memory with objective only" do
      memory = %Memory{objective: "Gain domain admin access"}
      result = Memory.serialize(memory)

      assert result =~ "## Track Memory"
      assert result =~ "**Objective:** Gain domain admin access"
    end

    test "serializes memory with focus" do
      memory = %Memory{focus: "Enumerating SMB shares"}
      result = Memory.serialize(memory)

      assert result =~ "**Focus:** Enumerating SMB shares"
    end

    test "serializes memory with tasks using checkbox format" do
      tasks = [
        %Task{id: "1", content: "Port scan", status: :completed},
        %Task{id: "2", content: "Check null sessions", status: :in_progress},
        %Task{id: "3", content: "AS-REP roasting", status: :pending}
      ]

      memory = %Memory{tasks: tasks}
      result = Memory.serialize(memory)

      assert result =~ "### Tasks"
      assert result =~ "- [x] Port scan"
      assert result =~ "- [ ] Check null sessions ← in progress"
      assert result =~ "- [ ] AS-REP roasting"
    end

    test "serializes memory with working notes" do
      memory = %Memory{working_notes: "DC likely at 10.0.0.5"}
      result = Memory.serialize(memory)

      assert result =~ "### Working Notes"
      assert result =~ "DC likely at 10.0.0.5"
    end

    test "serializes full memory with all fields" do
      tasks = [
        %Task{id: "1", content: "Port scan 10.0.0.0/24", status: :completed},
        %Task{id: "2", content: "Check for null sessions", status: :in_progress}
      ]

      memory = %Memory{
        objective: "Gain domain admin access on ACME-DC01",
        focus: "Enumerating SMB shares on 10.0.0.5",
        tasks: tasks,
        working_notes: "DC likely 10.0.0.5 based on reverse DNS lookup."
      }

      result = Memory.serialize(memory)

      assert result =~ "## Track Memory"
      assert result =~ "**Objective:** Gain domain admin access on ACME-DC01"
      assert result =~ "**Focus:** Enumerating SMB shares on 10.0.0.5"
      assert result =~ "### Tasks"
      assert result =~ "- [x] Port scan 10.0.0.0/24"
      assert result =~ "- [ ] Check for null sessions ← in progress"
      assert result =~ "### Working Notes"
      assert result =~ "DC likely 10.0.0.5 based on reverse DNS lookup."
    end
  end

  # ===========================================================================
  # Memory.to_map/1 Tests (for JSON/tool responses)
  # ===========================================================================

  describe "Memory.to_map/1" do
    test "converts memory to map with string keys" do
      task = %Task{id: "task-1", content: "Scan network", status: :completed}

      memory = %Memory{
        objective: "Objective",
        focus: "Focus",
        tasks: [task],
        working_notes: "Notes"
      }

      result = Memory.to_map(memory)

      assert result["objective"] == "Objective"
      assert result["focus"] == "Focus"
      assert result["working_notes"] == "Notes"
      assert length(result["tasks"]) == 1

      task_map = hd(result["tasks"])
      assert task_map["id"] == "task-1"
      assert task_map["content"] == "Scan network"
      assert task_map["status"] == "completed"
    end

    test "converts empty memory to map" do
      memory = Memory.new()
      result = Memory.to_map(memory)

      assert result["objective"] == nil
      assert result["focus"] == nil
      assert result["tasks"] == []
      assert result["working_notes"] == nil
    end
  end

  # ===========================================================================
  # Memory.inject/3 Tests
  # ===========================================================================

  describe "Memory.inject/3" do
    test "creates a ChatEntry memory snapshot" do
      memory = %Memory{
        objective: "Test objective",
        focus: "Test focus"
      }

      entry = Memory.inject(memory, "uuid-123", 1)

      assert entry.id == "uuid-123"
      assert entry.position == 1
      assert entry.entry_type == :memory
      assert entry.role == :user
      assert entry.message_type == :prompt
      assert entry.streaming == false
      assert entry.content =~ "## Track Memory"
      assert entry.content =~ "Test objective"
      assert entry.content =~ "Test focus"
    end

    test "creates ChatEntry with serialized memory content" do
      task = %Task{id: "1", content: "Port scan", status: :completed}
      memory = %Memory{tasks: [task]}

      entry = Memory.inject(memory, 42, 5)

      assert entry.id == 42
      assert entry.position == 5
      assert entry.content =~ "- [x] Port scan"
    end

    test "handles empty memory" do
      memory = Memory.new()

      entry = Memory.inject(memory, "empty", 1)

      assert entry.content =~ "*No memory set*"
    end
  end
end
