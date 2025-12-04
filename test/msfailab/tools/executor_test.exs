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

defmodule Msfailab.Tools.ExecutorTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tools.ContainerExecutor
  alias Msfailab.Tools.Executor
  alias Msfailab.Tools.MemoryExecutor
  alias Msfailab.Tools.MsfDataExecutor

  describe "behaviour definition" do
    test "defines handles_tool?/1 callback" do
      callbacks = Executor.behaviour_info(:callbacks)
      assert {:handles_tool?, 1} in callbacks
    end

    test "defines execute/3 callback" do
      callbacks = Executor.behaviour_info(:callbacks)
      assert {:execute, 3} in callbacks
    end
  end

  describe "dispatch/3" do
    test "returns error for unknown tool" do
      context = %{}

      assert {:error, {:unknown_tool, "nonexistent_tool"}} =
               Executor.dispatch("nonexistent_tool", %{}, context)
    end
  end

  describe "find_executor routing" do
    # Test that the correct executor is found for each tool type
    # without actually executing (which requires running services)

    test "MemoryExecutor handles memory tools" do
      assert MemoryExecutor.handles_tool?("read_memory")
      assert MemoryExecutor.handles_tool?("update_memory")
      assert MemoryExecutor.handles_tool?("add_task")
      assert MemoryExecutor.handles_tool?("update_task")
      assert MemoryExecutor.handles_tool?("remove_task")
    end

    test "MsfDataExecutor handles database tools" do
      assert MsfDataExecutor.handles_tool?("list_hosts")
      assert MsfDataExecutor.handles_tool?("list_services")
      assert MsfDataExecutor.handles_tool?("list_vulns")
      assert MsfDataExecutor.handles_tool?("create_note")
    end

    test "ContainerExecutor handles container tools" do
      assert ContainerExecutor.handles_tool?("execute_msfconsole_command")
      assert ContainerExecutor.handles_tool?("execute_bash_command")
    end

    test "executors don't handle unrelated tools" do
      refute MemoryExecutor.handles_tool?("list_hosts")
      refute MsfDataExecutor.handles_tool?("read_memory")
      refute ContainerExecutor.handles_tool?("list_hosts")
    end
  end

  describe "executors/0" do
    test "returns list of executor modules" do
      executors = Executor.executors()

      assert is_list(executors)
      assert length(executors) > 0
      assert MemoryExecutor in executors
      assert MsfDataExecutor in executors
      assert ContainerExecutor in executors
    end
  end
end
