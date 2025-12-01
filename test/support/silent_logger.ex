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

# coveralls-ignore-start
# Reason: Test support module - not production code
defmodule SilentLogger do
  @moduledoc """
  Silent logger backend for tests that captures logs in ETS while suppressing console output.

  This logger backend serves dual purposes during testing:
  1. **Suppresses console output** - Acts as a "black hole" for log messages, ensuring clean test output
  2. **Captures logs in ETS** - Stores all log messages for programmatic access by tests

  The logger maintains compatibility with ExUnit.CaptureLog, which hooks into the logger
  system at a higher level before messages reach this backend.

  ## Usage

  By default, this backend is active during all tests, keeping console output clean.
  To enable console logging for debugging while still capturing logs:

      PRINT_LOGS=true mix test

  Tests can access captured logs at any time:

      SilentLogger.get_logs()           # Get all captured logs
      SilentLogger.clear_logs()         # Clear the log buffer
  """

  @behaviour :gen_event

  @impl true
  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def init(name) when is_atom(name) do
    {:ok, configure(name, [])}
  end

  @impl true
  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(state.name, options, state)}
  end

  @impl true
  def handle_event({level, _gl, {Logger, message, _timestamp, _metadata}}, state) do
    # Store log entry in ETS for test assertions
    message_string = IO.chardata_to_string(message)
    :ets.insert(__MODULE__, {level, message_string})

    # Optionally print to console for debugging (PRINT_LOGS=true)
    if state.print_logs do
      IO.puts("[#{level}] #{message_string}")
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # Configuration helpers

  defp configure(name, options) do
    # Create ETS table on first configuration
    unless :ets.whereis(__MODULE__) != :undefined do
      :ets.new(__MODULE__, [:public, :named_table, :duplicate_bag])
    end

    env = Application.get_env(:logger, name, [])
    options = Keyword.merge(env, options)
    Application.put_env(:logger, name, options)

    level = Keyword.get(options, :level, :debug)
    print_logs = System.get_env("PRINT_LOGS") == "true"
    %{name: name, level: level, print_logs: print_logs}
  end

  defp configure(name, options, state) do
    env = Application.get_env(:logger, name, [])
    options = Keyword.merge(env, options)
    Application.put_env(:logger, name, options)

    level = Keyword.get(options, :level, :debug)
    print_logs = System.get_env("PRINT_LOGS") == "true"

    state
    |> Map.put(:level, level)
    |> Map.put(:print_logs, print_logs)
  end

  # Public API for accessing captured logs

  @doc """
  Gets all logs from the ETS table.

  Returns a list of `{level, message}` tuples in insertion order.

  ## Examples

      iex> SilentLogger.get_logs()
      [{:debug, "User logged in"}, {:info, "Email sent"}]
  """
  def get_logs do
    :ets.tab2list(__MODULE__)
  end

  @doc """
  Clears all logs from the ETS table.

  Useful for cleaning up between test scenarios or when starting fresh.

  ## Examples

      iex> SilentLogger.clear_logs()
      true
  """
  def clear_logs do
    :ets.delete_all_objects(__MODULE__)
  end
end

# coveralls-ignore-stop
