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

defmodule Msfailab.Tools.ContainerExecutor do
  @moduledoc """
  Executes container-based tools (execute_msfconsole_command, execute_bash_command).

  Unlike synchronous executors, container tools return `{:async, command_id}`
  immediately. The actual completion is signaled via events:

  - `execute_msfconsole_command` → `ConsoleUpdated` event when console becomes ready
  - `execute_bash_command` → `CommandResult` event with output

  ## Console Readiness

  For `execute_msfconsole_command`, the Metasploit console may not be immediately ready.
  This executor handles waiting internally - if the console returns
  `:console_starting` or `:console_busy`, the executor will retry with
  exponential backoff until the console is ready or timeout is reached.

  This encapsulates all console dependency knowledge within the container
  domain - callers don't need to know about console state.

  ## Usage

      case ContainerExecutor.execute("execute_bash_command", %{"command" => "ls"}, context) do
        {:async, command_id} -> # Track command_id for completion matching
        {:error, reason} -> # Handle error
      end
  """

  @behaviour Msfailab.Tools.Executor

  require Logger

  alias Msfailab.Containers

  @container_tools ~w(execute_msfconsole_command execute_bash_command)

  @impl true
  @spec handles_tool?(String.t()) :: boolean()
  def handles_tool?(tool_name), do: tool_name in @container_tools

  @impl true
  @spec execute(String.t(), map(), map()) ::
          {:async, String.t()} | {:error, term()}

  # coveralls-ignore-start
  # Reason: Container integration requiring real Docker/MSGRPC. Retry logic tested in retry_until_ready.
  def execute("execute_msfconsole_command", %{"command" => command}, context) do
    %{container_id: container_id, track_id: track_id} = context
    timing = retry_timing()

    execute_msf_with_retry(container_id, track_id, command, timing)
  end

  # coveralls-ignore-stop

  def execute("execute_msfconsole_command", _args, _context) do
    {:error, {:missing_parameter, "Missing required parameter: command"}}
  end

  # coveralls-ignore-start
  # Reason: Container integration requiring real Docker process.
  def execute("execute_bash_command", %{"command" => command}, context) do
    %{container_id: container_id, track_id: track_id} = context

    case Containers.send_bash_command(container_id, track_id, command) do
      {:ok, command_id} -> {:async, command_id}
      {:error, reason} -> {:error, reason}
    end
  end

  # coveralls-ignore-stop

  def execute("execute_bash_command", _args, _context) do
    {:error, {:missing_parameter, "Missing required parameter: command"}}
  end

  # ---------------------------------------------------------------------------
  # Console Readiness Retry Logic
  # ---------------------------------------------------------------------------

  @doc """
  Retry timing configuration for console readiness.

  Returns a map with timing parameters that can be overridden via application
  config `:msfailab, :container_executor_timing`.
  """
  @spec retry_timing() :: map()
  def retry_timing do
    defaults = %{
      initial_delay: 100,
      max_delay: 2_000,
      max_wait_time: 60_000
    }

    case Application.get_env(:msfailab, :container_executor_timing) do
      nil -> defaults
      overrides when is_map(overrides) -> Map.merge(defaults, overrides)
      _ -> defaults
    end
  end

  @doc """
  Executes msf_command with retry logic for console readiness.

  Retries with exponential backoff when console returns `:console_starting`
  or `:console_busy`. Returns immediately on success or permanent errors.

  ## Parameters

  - `container_id` - Container record ID
  - `track_id` - Track ID for console lookup
  - `command` - MSF command to execute
  - `timing` - Map with `:initial_delay`, `:max_delay`, `:max_wait_time`

  ## Returns

  - `{:async, command_id}` - Command accepted, completion via events
  - `{:error, :console_wait_timeout}` - Timed out waiting for console
  - `{:error, reason}` - Permanent error
  """
  @spec execute_msf_with_retry(integer(), integer(), String.t(), map()) ::
          {:async, String.t()} | {:error, term()}
  def execute_msf_with_retry(container_id, track_id, command, timing) do
    try_fn = fn -> Containers.send_metasploit_command(container_id, track_id, command) end
    retry_until_ready(try_fn, timing)
  end

  @doc """
  Retries a function with exponential backoff until success or timeout.

  The function should return:
  - `{:ok, result}` - Success, returns `{:async, result}`
  - `{:error, :console_starting}` - Retry after delay
  - `{:error, :console_busy}` - Retry after delay
  - `{:error, other}` - Permanent error, returns immediately

  ## Parameters

  - `try_fn` - Function to call, returns `{:ok, result}` or `{:error, reason}`
  - `timing` - Map with `:initial_delay`, `:max_delay`, `:max_wait_time`

  ## Examples

      iex> timing = %{initial_delay: 10, max_delay: 100, max_wait_time: 50}
      iex> try_fn = fn -> {:ok, "cmd-123"} end
      iex> ContainerExecutor.retry_until_ready(try_fn, timing)
      {:async, "cmd-123"}

      iex> timing = %{initial_delay: 10, max_delay: 100, max_wait_time: 5}
      iex> try_fn = fn -> {:error, :console_starting} end
      iex> ContainerExecutor.retry_until_ready(try_fn, timing)
      {:error, :console_wait_timeout}
  """
  @spec retry_until_ready((-> {:ok, term()} | {:error, term()}), map()) ::
          {:async, term()} | {:error, term()}
  def retry_until_ready(try_fn, timing) do
    start_time = System.monotonic_time(:millisecond)
    do_retry(try_fn, timing.initial_delay, start_time, timing)
  end

  defp do_retry(try_fn, delay, start_time, timing) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > timing.max_wait_time do
      # coveralls-ignore-next-line
      Logger.warning("msf_command timed out waiting for console (#{elapsed}ms)")
      {:error, {:console_timeout, "Console did not become ready in time"}}
    else
      case try_fn.() do
        {:ok, command_id} ->
          {:async, command_id}

        {:error, :console_starting} ->
          # coveralls-ignore-next-line
          Logger.debug("Console starting, waiting #{delay}ms before retry")
          Process.sleep(delay)
          next_delay = min(delay * 2, timing.max_delay)
          do_retry(try_fn, next_delay, start_time, timing)

        {:error, :console_busy} ->
          # coveralls-ignore-next-line
          Logger.debug("Console busy, waiting #{delay}ms before retry")
          Process.sleep(delay)
          next_delay = min(delay * 2, timing.max_delay)
          do_retry(try_fn, next_delay, start_time, timing)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
