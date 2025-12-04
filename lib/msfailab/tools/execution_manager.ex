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

defmodule Msfailab.Tools.ExecutionManager do
  @moduledoc """
  Orchestrates tool execution with mutex-based grouping.

  The ExecutionManager handles concurrent execution of tools with isolation guarantees:
  - Tools with the same mutex execute sequentially (in LLM-specified order)
  - Tools with `nil` mutex execute truly in parallel (one Task per tool)
  - Each tool runs in an isolated Task; crashes don't affect other tools
  - Status messages are sent back to the caller for state updates

  ## Execution Model

  ```
  execute_batch(tools, context, caller_pid)
      │
      ├── Group by mutex
      │
      ├── mutex: :msf_console ──► Task (sequential in LLM order)
      │       └── Sends {:tool_status, entry_id, status, result}
      │
      ├── mutex: :memory ──────► Task (sequential in LLM order)
      │       └── Sends {:tool_status, entry_id, status, result}
      │
      └── mutex: nil ──────────► Task per tool (true parallel)
              └── Each sends {:tool_status, entry_id, status, result}
  ```

  ## Mutex Groups

  | Mutex | Tools | Behavior |
  |-------|-------|----------|
  | `:msf_console` | `msf_command` | Sequential - console is single-threaded |
  | `:memory` | `read_memory`, `update_memory`, `add_task`, `update_task`, `remove_task` | Sequential - accumulate DB changes |
  | `nil` | `bash_command`, `list_*`, `retrieve_loot`, `create_note` | True parallel |

  ## Status Messages

  All tools send the same message format to the caller:

  - `{:tool_status, entry_id, :executing}` - Tool started
  - `{:tool_status, entry_id, :success, result}` - Tool completed successfully
  - `{:tool_status, entry_id, :error, reason}` - Tool failed
  - `{:tool_async, entry_id, command_id}` - Async tool started (completion via events)

  ## Example

      tools = [
        {1, %{tool_name: "list_hosts", arguments: %{}}},
        {2, %{tool_name: "msf_command", arguments: %{"command" => "help"}}}
      ]

      context = %{
        track_id: 123,
        workspace_slug: "my-project",
        container_id: 456
      }

      ExecutionManager.execute_batch(tools, context, self())

      receive do
        {:tool_status, entry_id, status, result} ->
          IO.puts("Tool \#{entry_id} completed with \#{status}")
      end
  """

  require Logger

  alias Msfailab.Tools
  alias Msfailab.Tools.Executor

  @type entry_id :: integer()
  @type tool_state :: %{tool_name: String.t(), arguments: map()}
  @type tool_entry :: {entry_id(), tool_state()}
  @type context :: Executor.context()

  @doc """
  Groups tools by their mutex value.

  Tools with the same mutex will be placed in the same group and executed
  sequentially. Tools with `nil` mutex are grouped together but will be
  executed in parallel (one Task per tool).

  ## Parameters

  - `tools` - List of `{entry_id, tool_state}` tuples

  ## Returns

  A map from mutex atom (or nil) to list of tools in that group.

  ## Example

      iex> tools = [{1, %{tool_name: "msf_command", arguments: %{}}}]
      iex> ExecutionManager.group_by_mutex(tools)
      %{msf_console: [{1, %{tool_name: "msf_command", arguments: %{}}}]}
  """
  @spec group_by_mutex([tool_entry()]) :: %{(atom() | nil) => [tool_entry()]}
  def group_by_mutex(tools) do
    tools
    |> Enum.group_by(fn {_entry_id, tool_state} ->
      get_tool_mutex(tool_state.tool_name)
    end)
  end

  @doc """
  Executes a batch of tools with mutex-based isolation.

  Groups tools by mutex, then spawns Tasks:
  - One Task per mutex group (executes tools sequentially within group)
  - One Task per nil-mutex tool (true parallel execution)

  Each Task sends status messages to the caller:
  - `{:tool_status, entry_id, :executing}` when starting
  - `{:tool_status, entry_id, :success, result}` on success
  - `{:tool_status, entry_id, :error, reason}` on failure
  - `{:tool_async, entry_id, command_id}` for async tools

  ## Parameters

  - `tools` - List of `{entry_id, tool_state}` tuples to execute
  - `context` - Execution context (track_id, workspace_slug, container_id, etc.)
  - `caller` - PID to send status messages to

  ## Example

      ExecutionManager.execute_batch(
        [{1, %{tool_name: "list_hosts", arguments: %{}}}],
        %{workspace_slug: "my-project"},
        self()
      )
  """
  @spec execute_batch([tool_entry()], context(), pid()) :: :ok
  def execute_batch(tools, context, caller) do
    groups = group_by_mutex(tools)

    # Spawn tasks for each group
    Enum.each(groups, fn {mutex, group_tools} ->
      spawn_group_execution(mutex, group_tools, context, caller)
    end)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Get mutex for a tool, defaulting to nil for unknown tools
  @spec get_tool_mutex(String.t()) :: atom() | nil
  defp get_tool_mutex(tool_name) do
    case Tools.get_tool(tool_name) do
      {:ok, tool} -> tool.mutex
      {:error, :not_found} -> nil
    end
  end

  # Spawn execution for a mutex group
  @spec spawn_group_execution(atom() | nil, [tool_entry()], context(), pid()) :: :ok
  defp spawn_group_execution(nil, tools, context, caller) do
    # nil mutex: spawn one task per tool (true parallel)
    Enum.each(tools, fn tool_entry ->
      Task.start(fn ->
        execute_tool_with_status(tool_entry, context, caller)
      end)
    end)

    :ok
  end

  defp spawn_group_execution(_mutex, tools, context, caller) do
    # Non-nil mutex: spawn one task that executes all tools sequentially
    Task.start(fn ->
      Enum.each(tools, fn tool_entry ->
        execute_tool_with_status(tool_entry, context, caller)
      end)
    end)

    :ok
  end

  # Execute a single tool and send status messages
  @spec execute_tool_with_status(tool_entry(), context(), pid()) :: :ok
  defp execute_tool_with_status({entry_id, tool_state}, context, caller) do
    # Send executing status
    send(caller, {:tool_status, entry_id, :executing})

    try do
      result = Executor.dispatch(tool_state.tool_name, tool_state.arguments, context)

      case result do
        {:ok, value} ->
          send(caller, {:tool_status, entry_id, :success, value})

        {:async, command_id} ->
          send(caller, {:tool_async, entry_id, command_id})

        {:error, reason} ->
          send(caller, {:tool_status, entry_id, :error, reason})
      end
    rescue
      error ->
        error_message = Exception.message(error)
        Logger.error("Tool execution crashed: #{tool_state.tool_name} - #{error_message}")
        send(caller, {:tool_status, entry_id, :error, error_message})
    end

    :ok
  end
end
