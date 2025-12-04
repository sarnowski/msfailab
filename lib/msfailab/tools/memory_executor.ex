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

defmodule Msfailab.Tools.MemoryExecutor do
  @moduledoc """
  Executes memory tools with self-contained DB persistence.

  Memory tools allow AI agents to maintain short-term memory across context
  compactions. Each tool reads from the database, modifies memory, writes back,
  and returns the result.

  ## Supported Tools

  | Tool | Description |
  |------|-------------|
  | `read_memory` | Get current memory state |
  | `update_memory` | Update objective, focus, or working_notes |
  | `add_task` | Add a new task to the list |
  | `update_task` | Update task content or status |
  | `remove_task` | Remove a task from the list |

  ## Context Requirements

  All tools require `track_id` in the context:

      MemoryExecutor.execute("read_memory", %{}, %{track_id: 123})

  ## Return Format

  All tools return `{:ok, result}` where result is the full memory state:

      {:ok, %{
        "objective" => "Gain domain admin access",
        "focus" => "Enumerating SMB shares",
        "tasks" => [
          %{"id" => "uuid", "content" => "Port scan", "status" => "completed"}
        ],
        "working_notes" => "DC likely at 10.0.0.5"
      }}
  """

  @behaviour Msfailab.Tools.Executor

  alias Msfailab.Tracks
  alias Msfailab.Tracks.Memory

  @memory_tools ~w(read_memory update_memory add_task update_task remove_task)

  @impl true
  @spec handles_tool?(String.t()) :: boolean()
  def handles_tool?(tool_name), do: tool_name in @memory_tools

  @impl true
  @spec execute(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}

  def execute("read_memory", _args, %{track_id: track_id}) do
    with {:ok, memory} <- load_memory(track_id) do
      {:ok, Memory.to_map(memory)}
    end
  end

  def execute("update_memory", args, %{track_id: track_id}) do
    with {:ok, memory} <- load_memory(track_id) do
      changes =
        args
        |> Map.take(["objective", "focus", "working_notes"])
        |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
        |> Map.new()

      updated = Memory.update(memory, changes)
      persist_and_return(track_id, updated)
    end
  end

  def execute("add_task", %{"content" => content}, %{track_id: track_id}) do
    with {:ok, memory} <- load_memory(track_id) do
      updated = Memory.add_task(memory, content)
      persist_and_return(track_id, updated)
    end
  end

  def execute("add_task", _args, %{track_id: _}) do
    {:error, {:missing_parameter, "Missing required parameter: content"}}
  end

  def execute("update_task", %{"id" => id} = args, %{track_id: track_id}) do
    with {:ok, memory} <- load_memory(track_id) do
      changes =
        args
        |> Map.take(["content", "status"])
        |> Enum.map(fn
          {"status", v} -> {:status, string_to_status(v)}
          {"content", v} -> {:content, v}
        end)
        |> Map.new()

      case Memory.update_task(memory, id, changes) do
        {:ok, updated} ->
          persist_and_return(track_id, updated)

        {:error, :task_not_found} ->
          {:error, {:task_not_found, "Task not found: #{id}"}}
      end
    end
  end

  def execute("update_task", _args, %{track_id: _}) do
    {:error, {:missing_parameter, "Missing required parameter: id"}}
  end

  def execute("remove_task", %{"id" => id}, %{track_id: track_id}) do
    with {:ok, memory} <- load_memory(track_id) do
      updated = Memory.remove_task(memory, id)
      persist_and_return(track_id, updated)
    end
  end

  def execute("remove_task", _args, %{track_id: _}) do
    {:error, {:missing_parameter, "Missing required parameter: id"}}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_memory(track_id) do
    case Tracks.get_track(track_id) do
      nil -> {:error, {:track_not_found, "Track not found"}}
      track -> {:ok, track.memory || Memory.new()}
    end
  end

  defp persist_and_return(track_id, memory) do
    case Tracks.update_track_memory(track_id, memory) do
      {:ok, _track} -> {:ok, Memory.to_map(memory)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp string_to_status("pending"), do: :pending
  defp string_to_status("in_progress"), do: :in_progress
  defp string_to_status("completed"), do: :completed
end
