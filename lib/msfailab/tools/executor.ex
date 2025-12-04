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

defmodule Msfailab.Tools.Executor do
  @moduledoc """
  Behaviour for tool executors.

  All tool executors must implement this behaviour, providing a uniform interface
  for tool execution regardless of the underlying implementation (container-based,
  database, or in-memory).

  ## Return Types

  All executors return one of:

  - `{:ok, result}` - Synchronous success with JSON-serializable result
  - `{:async, command_id}` - Asynchronous execution started (completion via events)
  - `{:error, reason}` - Execution failed

  ## Example

      defmodule MyExecutor do
        @behaviour Msfailab.Tools.Executor

        @impl true
        def handles_tool?("my_tool"), do: true
        def handles_tool?(_), do: false

        @impl true
        def execute("my_tool", args, context) do
          {:ok, %{result: "done"}}
        end
      end
  """

  @type context :: %{
          optional(:track_id) => pos_integer(),
          optional(:workspace_slug) => String.t(),
          optional(:container_id) => pos_integer(),
          optional(atom()) => term()
        }

  @type result ::
          {:ok, term()}
          | {:async, String.t()}
          | {:error, term()}

  @doc """
  Returns true if this executor handles the given tool.
  """
  @callback handles_tool?(tool_name :: String.t()) :: boolean()

  @doc """
  Execute a tool with the given arguments and context.

  ## Returns

  - `{:ok, result}` - Synchronous success
  - `{:async, command_id}` - Asynchronous execution started
  - `{:error, reason}` - Execution failed
  """
  @callback execute(tool_name :: String.t(), arguments :: map(), context :: context()) :: result()

  @executors [
    Msfailab.Tools.MemoryExecutor,
    Msfailab.Tools.MsfDataExecutor,
    Msfailab.Tools.ContainerExecutor
  ]

  @doc """
  Returns the list of registered executor modules.
  """
  @spec executors() :: [module()]
  def executors, do: @executors

  @doc """
  Dispatch a tool execution to the appropriate executor.

  Finds the first executor that handles the tool and delegates to it.
  Returns `{:error, {:unknown_tool, tool_name}}` if no executor handles it.
  """
  @spec dispatch(String.t(), map(), context()) :: result()
  def dispatch(tool_name, arguments, context) do
    case find_executor(tool_name) do
      nil -> {:error, {:unknown_tool, tool_name}}
      executor -> executor.execute(tool_name, arguments, context)
    end
  end

  defp find_executor(tool_name) do
    Enum.find(@executors, fn executor ->
      executor.handles_tool?(tool_name)
    end)
  end
end
