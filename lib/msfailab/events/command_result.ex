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

defmodule Msfailab.Events.CommandResult do
  @moduledoc """
  Event broadcast when command execution progresses or completes.

  This event extends CommandIssued with execution results. It includes all
  fields from CommandIssued (type, command) plus output and status information,
  enabling self-healing state reconstruction.

  ## Statuses

  - `status: :running` - Command is executing, output accumulated so far
  - `status: :finished` - Command completed (regardless of exit code)
  - `status: :error` - Command could not be executed (e.g., MSGRPC not ready)

  Note that `status: :error` means the command could not be run at all.
  A command that runs but exits with non-zero is still `:finished` - we don't
  interpret the command's exit code as success/failure.

  For Metasploit commands, output is polled periodically and accumulated.
  For bash commands, output is available when the command completes.

  ## Fields (from CommandIssued)

  - `workspace_id` - The workspace containing this container
  - `container_id` - The container where the command is executing
  - `track_id` - The track that issued the command
  - `command_id` - Unique identifier matching the CommandIssued event
  - `type` - Either `:metasploit` or `:bash`
  - `command` - The command string that was submitted

  ## Additional Fields

  - `output` - Accumulated output (empty string for error status)
  - `prompt` - Current console prompt (Metasploit only, empty string otherwise)
  - `status` - `:running`, `:finished`, or `:error`
  - `exit_code` - Exit code (only for bash commands when finished)
  - `error` - Error reason (only when status is :error)
  - `timestamp` - When this event was generated

  ## Self-Healing

  If a subscriber misses CommandIssued but receives this event,
  they can reconstruct the command context since type and command
  are included.
  """

  alias Msfailab.Events.CommandIssued

  @type status :: :running | :finished | :error
  @type command_type :: :metasploit | :bash

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer(),
          command_id: String.t(),
          type: command_type(),
          command: String.t(),
          output: String.t(),
          prompt: String.t(),
          status: status(),
          exit_code: integer() | nil,
          error: term() | nil,
          timestamp: DateTime.t()
        }

  @enforce_keys [
    :workspace_id,
    :container_id,
    :track_id,
    :command_id,
    :type,
    :command,
    :output,
    :prompt,
    :status,
    :timestamp
  ]
  defstruct [
    :workspace_id,
    :container_id,
    :track_id,
    :command_id,
    :type,
    :command,
    :output,
    :prompt,
    :status,
    :exit_code,
    :error,
    :timestamp
  ]

  @doc """
  Creates a new CommandResult event for a running command.

  Takes the original CommandIssued event to ensure all context is preserved
  for self-healing.

  ## Options

  - `:prompt` - Current console prompt (defaults to empty string)

  ## Examples

      iex> issued = CommandIssued.new(1, 2, 42, "abc123", :metasploit, "db_status")
      iex> CommandResult.running(issued, "Scanning...", prompt: "msf6 > ")
      %CommandResult{status: :running, type: :metasploit, prompt: "msf6 > ", ...}
  """
  @spec running(CommandIssued.t(), String.t(), keyword()) :: t()
  def running(%CommandIssued{} = issued, output, opts \\ []) do
    %__MODULE__{
      workspace_id: issued.workspace_id,
      container_id: issued.container_id,
      track_id: issued.track_id,
      command_id: issued.command_id,
      type: issued.type,
      command: issued.command,
      output: output,
      prompt: Keyword.get(opts, :prompt, ""),
      status: :running,
      exit_code: nil,
      error: nil,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new CommandResult event for a finished command.

  Takes the original CommandIssued event to ensure all context is preserved
  for self-healing.

  Note: A finished command may have any exit code. We don't interpret
  the exit code - that's up to the caller.

  ## Options

  - `:exit_code` - Exit code for bash commands (nil for Metasploit)
  - `:prompt` - Current console prompt (defaults to empty string)

  ## Examples

      iex> issued = CommandIssued.new(1, 2, 42, "abc123", :bash, "ls -la")
      iex> CommandResult.finished(issued, "Done!", exit_code: 0)
      %CommandResult{status: :finished, exit_code: 0, type: :bash, ...}

      iex> issued = CommandIssued.new(1, 2, 42, "abc123", :metasploit, "db_status")
      iex> CommandResult.finished(issued, "Connected", prompt: "msf6 > ")
      %CommandResult{status: :finished, prompt: "msf6 > ", ...}
  """
  @spec finished(CommandIssued.t(), String.t(), keyword()) :: t()
  def finished(%CommandIssued{} = issued, output, opts \\ []) do
    %__MODULE__{
      workspace_id: issued.workspace_id,
      container_id: issued.container_id,
      track_id: issued.track_id,
      command_id: issued.command_id,
      type: issued.type,
      command: issued.command,
      output: output,
      prompt: Keyword.get(opts, :prompt, ""),
      status: :finished,
      exit_code: Keyword.get(opts, :exit_code),
      error: nil,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new CommandResult event for a command that could not be executed.

  Takes the original CommandIssued event to ensure all context is preserved
  for self-healing.

  This is used when the command fails before it can run, such as when
  MSGRPC is not ready or console creation fails.

  ## Examples

      iex> issued = CommandIssued.new(1, 2, 42, "abc123", :metasploit, "db_status")
      iex> CommandResult.error(issued, :msgrpc_not_ready)
      %CommandResult{status: :error, error: :msgrpc_not_ready, type: :metasploit, ...}

      iex> CommandResult.error(issued, {:console_create_failed, :timeout})
      %CommandResult{status: :error, error: {:console_create_failed, :timeout}, ...}
  """
  @spec error(CommandIssued.t(), term()) :: t()
  def error(%CommandIssued{} = issued, error) do
    %__MODULE__{
      workspace_id: issued.workspace_id,
      container_id: issued.container_id,
      track_id: issued.track_id,
      command_id: issued.command_id,
      type: issued.type,
      command: issued.command,
      output: "",
      prompt: "",
      status: :error,
      exit_code: nil,
      error: error,
      timestamp: DateTime.utc_now()
    }
  end
end
