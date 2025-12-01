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

defmodule Msfailab.Events.ConsoleUpdated do
  @moduledoc """
  Event broadcast when a console's status changes or produces output.

  This event is emitted by Console GenServer during normal operation, and by
  Container when Console dies (since a dead process cannot emit events).

  ## Statuses

  - `:offline` - Not connected. Container not running, or console destroyed.
  - `:starting` - Console created via `console.create`, reading initialization output.
  - `:ready` - Idle, can accept commands.
  - `:busy` - Command executing, polling for output.

  ## Fields

  - `workspace_id` - The workspace containing this container
  - `container_id` - The container where the console lives
  - `track_id` - The track that owns this console
  - `status` - Current console status
  - `command_id` - Command correlation ID (present when executing a command)
  - `command` - The command string (present when executing a command)
  - `output` - Output delta since last event (accumulated by subscribers)
  - `prompt` - Current console prompt (set when transitioning to :ready)
  - `timestamp` - When this event was generated

  ## Event Emission Responsibility

  | Status | Emitted By | When |
  |--------|------------|------|
  | `:offline` | **Container** | Console crashes/stops (dead process can't emit) |
  | `:starting` | Console | After `console.create`, with output chunks |
  | `:ready` | Console | Initialization complete or command complete |
  | `:busy` | Console | Command sent, with output chunks |

  ## Output Accumulation

  The `output` field contains only the delta since the last event. Subscribers
  (like TrackServer) are responsible for accumulating output into their history.
  """

  @type status :: :offline | :starting | :ready | :busy

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer(),
          status: status(),
          command_id: String.t() | nil,
          command: String.t() | nil,
          output: String.t(),
          prompt: String.t(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :container_id, :track_id, :status, :output, :prompt, :timestamp]
  defstruct [
    :workspace_id,
    :container_id,
    :track_id,
    :status,
    :command_id,
    :command,
    :output,
    :prompt,
    :timestamp
  ]

  @doc """
  Creates a ConsoleUpdated event for when a console goes offline.

  This is typically emitted by Container when it detects a Console process
  has died, since a dead process cannot emit its own events.

  ## Examples

      iex> ConsoleUpdated.offline(1, 2, 42)
      %ConsoleUpdated{status: :offline, output: "", prompt: "", ...}
  """
  @spec offline(integer(), integer(), integer()) :: t()
  def offline(workspace_id, container_id, track_id) do
    %__MODULE__{
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id,
      status: :offline,
      command_id: nil,
      command: nil,
      output: "",
      prompt: "",
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a ConsoleUpdated event for console initialization output.

  Used during the `:starting` phase when the console is outputting its
  initialization banner.

  ## Examples

      iex> ConsoleUpdated.starting(1, 2, 42, "=[ metasploit v6.x ]...")
      %ConsoleUpdated{status: :starting, output: "=[ metasploit v6.x ]...", ...}
  """
  @spec starting(integer(), integer(), integer(), String.t()) :: t()
  def starting(workspace_id, container_id, track_id, output) do
    %__MODULE__{
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id,
      status: :starting,
      command_id: nil,
      command: nil,
      output: output,
      prompt: "",
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a ConsoleUpdated event for when the console becomes ready.

  This indicates the console has finished initialization or a command has
  completed. The prompt indicates the current console state.

  ## Examples

      iex> ConsoleUpdated.ready(1, 2, 42, "msf6 > ")
      %ConsoleUpdated{status: :ready, prompt: "msf6 > ", ...}
  """
  @spec ready(integer(), integer(), integer(), String.t()) :: t()
  def ready(workspace_id, container_id, track_id, prompt) do
    %__MODULE__{
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id,
      status: :ready,
      command_id: nil,
      command: nil,
      output: "",
      prompt: prompt,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a ConsoleUpdated event for command execution output.

  Used during the `:busy` phase when a command is executing and producing
  output. The command_id and command are included for correlation.

  ## Examples

      iex> ConsoleUpdated.busy(1, 2, 42, "abc123", "db_status", "[*] Connected...")
      %ConsoleUpdated{status: :busy, command_id: "abc123", output: "[*] Connected...", ...}
  """
  @spec busy(integer(), integer(), integer(), String.t(), String.t(), String.t()) :: t()
  def busy(workspace_id, container_id, track_id, command_id, command, output) do
    %__MODULE__{
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id,
      status: :busy,
      command_id: command_id,
      command: command,
      output: output,
      prompt: "",
      timestamp: DateTime.utc_now()
    }
  end
end
