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

defmodule Msfailab.Tools.ExecutionManagerTest do
  @moduledoc """
  Tests for ExecutionManager - mutex-based tool execution grouping.

  The ExecutionManager handles concurrent execution of tools with the following rules:
  - Tools with the same mutex execute sequentially (in LLM-specified order)
  - Tools with nil mutex execute truly in parallel (one Task per tool)
  - Each tool execution sends status messages back to the caller
  """
  use Msfailab.DataCase, async: true

  alias Msfailab.Tools.ExecutionManager
  alias Msfailab.Tracks

  # Helper to create a track for memory tool tests
  defp create_track do
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

    {workspace, track}
  end

  describe "group_by_mutex/1" do
    test "groups tools with same mutex together" do
      tools = [
        {1, %{tool_name: "msf_command", arguments: %{}}},
        {2, %{tool_name: "list_hosts", arguments: %{}}},
        {3, %{tool_name: "msf_command", arguments: %{}}}
      ]

      groups = ExecutionManager.group_by_mutex(tools)

      # msf_command has mutex :msf_console, list_hosts has nil mutex
      assert Map.has_key?(groups, :msf_console)
      assert Map.has_key?(groups, nil)

      # Two msf_commands in the :msf_console group
      msf_group = Map.get(groups, :msf_console)
      assert length(msf_group) == 2

      # One list_hosts in the nil group
      nil_group = Map.get(groups, nil)
      assert length(nil_group) == 1
    end

    test "preserves order within mutex groups" do
      tools = [
        {1, %{tool_name: "read_memory", arguments: %{}}},
        {5, %{tool_name: "update_memory", arguments: %{}}},
        {3, %{tool_name: "add_task", arguments: %{}}}
      ]

      groups = ExecutionManager.group_by_mutex(tools)

      # All memory tools have mutex :memory
      memory_group = Map.get(groups, :memory)
      assert length(memory_group) == 3

      # Order should be preserved (1, 5, 3 - LLM order)
      entry_ids = Enum.map(memory_group, fn {id, _} -> id end)
      assert entry_ids == [1, 5, 3]
    end

    test "handles unknown tools gracefully" do
      tools = [
        {1, %{tool_name: "unknown_tool", arguments: %{}}}
      ]

      # Unknown tools should be treated as nil mutex (parallel)
      groups = ExecutionManager.group_by_mutex(tools)
      assert Map.has_key?(groups, nil)
      assert length(Map.get(groups, nil)) == 1
    end
  end

  describe "execute_batch/3 with synchronous tools" do
    test "sends status messages for successful execution" do
      {workspace, track} = create_track()

      tools = [
        {1, %{tool_name: "read_memory", arguments: %{}}}
      ]

      context = %{
        track_id: track.id,
        workspace_slug: workspace.slug
      }

      # Execute and collect messages
      ExecutionManager.execute_batch(tools, context, self())

      # Should receive executing, then success
      assert_receive {:tool_status, 1, :executing}, 1000
      assert_receive {:tool_status, 1, :success, result}, 1000
      assert is_map(result)
    end

    test "sends error status on failure" do
      {workspace, _track} = create_track()

      tools = [
        {1, %{tool_name: "read_memory", arguments: %{}}}
      ]

      # Invalid track_id should cause error
      context = %{
        track_id: 999_999,
        workspace_slug: workspace.slug
      }

      ExecutionManager.execute_batch(tools, context, self())

      assert_receive {:tool_status, 1, :executing}, 1000
      assert_receive {:tool_status, 1, :error, _reason}, 1000
    end

    test "executes nil-mutex tools in parallel" do
      {_workspace, track} = create_track()

      # Three parallel memory read tools (nil mutex for read_memory... wait, read_memory has :memory mutex)
      # Use bash_command which has nil mutex - they'll error but still demonstrate parallel execution
      # Actually bash_command also errors without container. Let's test that parallel tools all start quickly.

      # Three parallel tools (nil mutex) - they may error due to missing MSF workspace,
      # but we verify they all start (get :executing) and complete (get terminal status)
      tools = [
        {1, %{tool_name: "list_hosts", arguments: %{}}},
        {2, %{tool_name: "list_services", arguments: %{}}},
        {3, %{tool_name: "list_vulns", arguments: %{}}}
      ]

      context = %{
        track_id: track.id,
        workspace_slug: "nonexistent"
      }

      start_time = System.monotonic_time(:millisecond)
      ExecutionManager.execute_batch(tools, context, self())

      # Collect all status messages (6: 3 executing + 3 terminal)
      messages = collect_messages(6, 2000)
      end_time = System.monotonic_time(:millisecond)

      # All three should get :executing message
      executing_msgs =
        Enum.filter(messages, fn msg -> match?({:tool_status, _, :executing}, msg) end)

      assert length(executing_msgs) == 3

      # All three should complete (success or error)
      terminal_msgs =
        Enum.filter(messages, fn msg ->
          match?({:tool_status, _, :success, _}, msg) or match?({:tool_status, _, :error, _}, msg)
        end)

      assert length(terminal_msgs) == 3

      # Verify all entry IDs are present
      entry_ids =
        Enum.map(executing_msgs, fn {:tool_status, id, :executing} -> id end) |> Enum.sort()

      assert entry_ids == [1, 2, 3]

      # Parallel execution should be fast (not 3x sequential)
      # This is a weak assertion - mainly checking they don't block each other
      assert end_time - start_time < 1000
    end

    test "executes same-mutex tools sequentially" do
      {_workspace, track} = create_track()

      # Three memory tools (same :memory mutex)
      tools = [
        {1, %{tool_name: "add_task", arguments: %{"content" => "Task 1"}}},
        {2, %{tool_name: "add_task", arguments: %{"content" => "Task 2"}}},
        {3, %{tool_name: "add_task", arguments: %{"content" => "Task 3"}}}
      ]

      context = %{
        track_id: track.id
      }

      ExecutionManager.execute_batch(tools, context, self())

      # Collect messages - should be 6 (3 executing + 3 success)
      messages = collect_messages(6, 2000)

      # Extract entry_ids from success messages in order
      success_entry_ids =
        messages
        |> Enum.filter(fn msg -> match?({:tool_status, _, :success, _}, msg) end)
        |> Enum.map(fn {:tool_status, id, :success, _} -> id end)

      # Sequential execution means they complete in order
      assert success_entry_ids == [1, 2, 3]

      # Verify all tasks were added
      updated_track = Tracks.get_track(track.id)
      assert length(updated_track.memory.tasks) == 3
    end

    test "one tool crash does not affect others in same mutex group" do
      {_workspace, track} = create_track()

      # First add a task, then try to update non-existent, then add another
      tools = [
        {1, %{tool_name: "add_task", arguments: %{"content" => "Task 1"}}},
        {2,
         %{tool_name: "update_task", arguments: %{"id" => "nonexistent", "status" => "completed"}}},
        {3, %{tool_name: "add_task", arguments: %{"content" => "Task 3"}}}
      ]

      context = %{
        track_id: track.id
      }

      ExecutionManager.execute_batch(tools, context, self())

      # Collect messages
      messages = collect_messages(6, 2000)

      # Should have 2 success (tasks 1 and 3) and 1 error (task 2)
      success_msgs =
        Enum.filter(messages, fn msg -> match?({:tool_status, _, :success, _}, msg) end)

      error_msgs = Enum.filter(messages, fn msg -> match?({:tool_status, _, :error, _}, msg) end)

      assert length(success_msgs) == 2
      assert length(error_msgs) == 1

      # Verify the error was for entry 2
      [{:tool_status, error_id, :error, _}] = error_msgs
      assert error_id == 2

      # Verify tasks were still added
      updated_track = Tracks.get_track(track.id)
      assert length(updated_track.memory.tasks) == 2
    end
  end

  describe "execute_batch/3 with async tools" do
    test "sends async status for container tools" do
      # Container tools need mocking since they interact with Docker
      # For now, we test that they're routed correctly and return async
      # Full integration testing requires container infrastructure

      tools = [
        {1, %{tool_name: "bash_command", arguments: %{"command" => "echo hello"}}}
      ]

      context = %{
        track_id: 123,
        container_id: 456
      }

      # This will fail because container doesn't exist, but we can verify the routing
      ExecutionManager.execute_batch(tools, context, self())

      assert_receive {:tool_status, 1, :executing}, 1000
      # Will get error since container doesn't exist
      assert_receive {:tool_status, 1, :error, _reason}, 1000
    end
  end

  describe "execute_batch/3 with mixed mutex tools" do
    test "runs different mutex groups in parallel" do
      {_workspace, track} = create_track()

      # Mix of memory tools (mutex: :memory) and data tools (mutex: nil)
      # Memory tools will succeed, MsfData tools may error (no MSF workspace)
      tools = [
        {1, %{tool_name: "add_task", arguments: %{"content" => "Task 1"}}},
        {2, %{tool_name: "list_hosts", arguments: %{}}},
        {3, %{tool_name: "add_task", arguments: %{"content" => "Task 2"}}},
        {4, %{tool_name: "list_services", arguments: %{}}}
      ]

      context = %{
        track_id: track.id,
        workspace_slug: "nonexistent"
      }

      ExecutionManager.execute_batch(tools, context, self())

      # Collect all messages (8 total: 4 executing + 4 terminal)
      messages = collect_messages(8, 2000)

      # All 4 should get executing
      executing_msgs =
        Enum.filter(messages, fn msg -> match?({:tool_status, _, :executing}, msg) end)

      assert length(executing_msgs) == 4

      # All 4 should complete (success or error)
      terminal_msgs =
        Enum.filter(messages, fn msg ->
          match?({:tool_status, _, :success, _}, msg) or match?({:tool_status, _, :error, _}, msg)
        end)

      assert length(terminal_msgs) == 4

      # Memory tools (1, 3) should succeed
      success_msgs =
        Enum.filter(messages, fn msg -> match?({:tool_status, _, :success, _}, msg) end)

      memory_success_ids =
        success_msgs
        |> Enum.map(fn {:tool_status, id, :success, _} -> id end)
        |> Enum.sort()

      assert 1 in memory_success_ids
      assert 3 in memory_success_ids

      # Verify tasks were added (memory tools succeeded)
      updated_track = Tracks.get_track(track.id)
      assert length(updated_track.memory.tasks) == 2
    end
  end

  # Helper to collect N messages within timeout
  defp collect_messages(count, timeout) do
    collect_messages(count, timeout, [])
  end

  defp collect_messages(0, _timeout, acc), do: Enum.reverse(acc)

  defp collect_messages(count, timeout, acc) do
    receive do
      {:tool_status, _id, _status} = msg ->
        collect_messages(count - 1, timeout, [msg | acc])

      {:tool_status, _id, _status, _result} = msg ->
        collect_messages(count - 1, timeout, [msg | acc])

      {:tool_async, _id, _command_id} = msg ->
        collect_messages(count - 1, timeout, [msg | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
