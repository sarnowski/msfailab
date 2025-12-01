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

defmodule Msfailab.Events.CommandIssued do
  @moduledoc """
  Event broadcast when a command is submitted for execution.

  This event is emitted as soon as a command is accepted for execution,
  before any output is available. It allows UIs to immediately show
  that a command is in progress.

  ## Command Types

  - `:metasploit` - Command sent to the Metasploit console via MSGRPC
  - `:bash` - Shell command executed in the container via Docker exec

  ## Fields

  - `workspace_id` - The workspace containing this container and track
  - `container_id` - The container where the command executes
  - `track_id` - The track that issued the command
  - `command_id` - Unique identifier for this command execution
  - `type` - Either `:metasploit` or `:bash`
  - `command` - The command string that was submitted
  - `timestamp` - When the command was issued
  """

  @type command_type :: :metasploit | :bash

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer(),
          command_id: String.t(),
          type: command_type(),
          command: String.t(),
          timestamp: DateTime.t()
        }

  @enforce_keys [
    :workspace_id,
    :container_id,
    :track_id,
    :command_id,
    :type,
    :command,
    :timestamp
  ]
  defstruct [:workspace_id, :container_id, :track_id, :command_id, :type, :command, :timestamp]

  @doc """
  Creates a new CommandIssued event.

  ## Examples

      iex> CommandIssued.new(1, 2, 42, "abc123", :metasploit, "db_status")
      %CommandIssued{workspace_id: 1, container_id: 2, track_id: 42, command_id: "abc123", ...}
  """
  @spec new(integer(), integer(), integer(), String.t(), command_type(), String.t()) :: t()
  def new(workspace_id, container_id, track_id, command_id, type, command) do
    %__MODULE__{
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id,
      command_id: command_id,
      type: type,
      command: command,
      timestamp: DateTime.utc_now()
    }
  end
end
